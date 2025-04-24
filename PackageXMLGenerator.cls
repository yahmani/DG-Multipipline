/**
 * @description Class responsible for generating package.xml files from Copado promotion changes
 * Handles both standard Salesforce metadata and Vlocity components
 */
public class PackageXMLGenerator {
    /**
     * @description Enum defining the different types of operations that can be performed on metadata
     */
    public enum CopadoOperation {
        ADD_NEW,        // New component added
        FULL_OP,        // Full operation (typically used for updates)
        DEL_OP,         // Component deletion
        RETR_ONLY,      // Retrieve only operation
        SEL_COMMIT      // Selective commit operation
    }
    
    /**
     * @description Main method to generate package.xml from a User Story's promotion changes
     * @param userStoryID The ID of the User Story containing the changes
     * @throws CustomException if the process fails
     */
    static void generatePackageXML(String userStoryID) {
        try {
            if(String.isBlank(userStoryID)) {
                throw new CustomException('User Story ID cannot be null or empty');
            }

            // Query for JSON files containing promotion changes
            // Files must be named 'Copado Promotion changes' and have .json extension
            List<ContentDocumentLink> clList = [SELECT Id, LinkedEntityId, ContentDocumentId, 
                                               ContentDocument.Title, ContentDocument.FileExtension 
                                               FROM ContentDocumentLink 
                                               WHERE LinkedEntityId = :userStoryID 
                                               AND ContentDocument.Title LIKE 'Copado Promotion changes%'
                                               AND ContentDocument.FileExtension = 'json'
                                               ORDER BY ContentDocument.CreatedDate DESC];
            
            if(clList.isEmpty()) {
                throw new CustomException('No promotion changes files found');
            }

            // Initialize maps to store different types of components
            Map<String, Set<String>> metadataMap = new Map<String, Set<String>>();      // Standard metadata
            Map<String, Set<String>> vlocityMap = new Map<String, Set<String>>();       // Vlocity components
            Map<String, Set<String>> deletedComponents = new Map<String, Set<String>>(); // Deleted components

            // Process each JSON file containing changes
            for(ContentDocumentLink cdl : clList) {
                // Get the latest version of the file
                List<ContentVersion> cvList = [SELECT VersionData 
                                              FROM ContentVersion 
                                              WHERE ContentDocumentId = :cdl.ContentDocumentId 
                                              AND IsLatest = true 
                                              LIMIT 1];
                
                if(cvList.isEmpty()) {
                    continue;
                }

                // Parse and process the JSON content
                String jsonContent = cvList[0].VersionData.toString();
                if(String.isBlank(jsonContent)) {
                    continue;
                }

                try {
                    List<Object> changes = (List<Object>)JSON.deserializeUntyped(jsonContent);
                    if(changes == null || changes.isEmpty()) {
                        continue;
                    }

                    processChanges(changes, metadataMap, vlocityMap, deletedComponents);
                } catch(Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Error processing JSON content: ' + e.getMessage());
                    continue;
                }
            }

            // Remove any components that were marked for deletion
            removeDeletedComponents(metadataMap, deletedComponents);

            if(metadataMap.isEmpty() && vlocityMap.isEmpty()) {
                throw new CustomException('No valid metadata found to process');
            }

            // Generate and save the package.xml file
            String packageXML = generatePackageXMLContent(metadataMap, vlocityMap);
            savePackageXML(packageXML, userStoryID);

            System.debug(LoggingLevel.INFO, 'Successfully generated package.xml');

        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating package.xml: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }

    /**
     * @description Processes the changes from JSON and categorizes them into appropriate maps
     * @param changes List of change objects from JSON
     * @param metadataMap Map to store standard metadata components
     * @param vlocityMap Map to store Vlocity components
     * @param deletedComponents Map to store components marked for deletion
     */
    private static void processChanges(List<Object> changes, 
                                      Map<String, Set<String>> metadataMap, 
                                      Map<String, Set<String>> vlocityMap,
                                      Map<String, Set<String>> deletedComponents) {
        for(Object changeObj : changes) {
            if(changeObj == null) continue;

            Map<String, Object> change = (Map<String, Object>)changeObj;
            if(change == null || change.isEmpty()) continue;

            // Extract change details from JSON
            String action = (String)change.get('a');  // Action type
            String type = (String)change.get('t');    // Metadata type
            String name = (String)change.get('n');    // Component name

            if(String.isBlank(action) || String.isBlank(type) || String.isBlank(name)) continue;

            CopadoOperation operation = getCopadoOperation(action);

            // Handle deleted components separately
            if(operation == CopadoOperation.DEL_OP) {
                if(!deletedComponents.containsKey(type)) {
                    deletedComponents.put(type, new Set<String>());
                }
                deletedComponents.get(type).add(name);
                continue;
            }

            // Skip components marked for retrieve only
            if(operation == CopadoOperation.RETR_ONLY) {
                continue;
            }

            // Process component based on whether it's Vlocity or standard
            if(change.containsKey('j') && change.get('j') != null) {
                processVlocityComponent(change, name, vlocityMap, operation);
            } else {
                if(!metadataMap.containsKey(type)) {
                    metadataMap.put(type, new Set<String>());
                }
                metadataMap.get(type).add(name);
            }
        }
    }

    /**
     * @description Removes components marked for deletion from the metadata map
     * @param metadataMap Map containing all metadata components
     * @param deletedComponents Map containing components to be deleted
     */
    private static void removeDeletedComponents(Map<String, Set<String>> metadataMap, 
                                              Map<String, Set<String>> deletedComponents) {
        for(String type : deletedComponents.keySet()) {
            if(metadataMap.containsKey(type)) {
                metadataMap.get(type).removeAll(deletedComponents.get(type));
                if(metadataMap.get(type).isEmpty()) {
                    metadataMap.remove(type);
                }
            }
        }
    }

    /**
     * @description Processes Vlocity-specific components from the changes
     * @param change The change object containing Vlocity data
     * @param name The name of the component
     * @param vlocityMap Map to store Vlocity components
     * @param operation The type of operation being performed
     */
    private static void processVlocityComponent(Map<String, Object> change, 
                                               String name, 
                                               Map<String, Set<String>> vlocityMap, 
                                               CopadoOperation operation) {
        try {
            String jsonStr = (String)change.get('j');
            if(String.isBlank(jsonStr)) return;

            // Parse Vlocity-specific JSON data
            Map<String, Object> vlocityData = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            if(vlocityData == null || !vlocityData.containsKey('vk')) return;

            String vlocityKey = (String)vlocityData.get('vk');
            if(String.isBlank(vlocityKey)) return;

            // Extract Vlocity type from the key
            List<String> keyParts = vlocityKey.split('/');
            if(keyParts.isEmpty()) return;

            String vlocityType = keyParts[0];
            if(!vlocityMap.containsKey(vlocityType)) {
                vlocityMap.put(vlocityType, new Set<String>());
            }
            vlocityMap.get(vlocityType).add(name);
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error processing Vlocity component: ' + e.getMessage());
        }
    }

    /**
     * @description Generates the content of the package.xml file
     * @param metadataMap Map containing standard metadata components
     * @param vlocityMap Map containing Vlocity components
     * @return String The generated package.xml content
     */
    private static String generatePackageXMLContent(Map<String, Set<String>> metadataMap, 
                                                   Map<String, Set<String>> vlocityMap) {
        String packageXML = '<?xml version="1.0" encoding="UTF-8"?>\n' +
                           '<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n';

        // Add standard metadata types
        for(String type : metadataMap.keySet()) {
            Set<String> members = metadataMap.get(type);
            if(members == null || members.isEmpty()) continue;

            packageXML += '    <types>\n';
            for(String member : new List<String>(members)) {
                packageXML += '        <members>' + member.escapeXml() + '</members>\n';
            }
            packageXML += '        <name>' + type.escapeXml() + '</name>\n';
            packageXML += '    </types>\n';
        }

        // Add Vlocity components if present
        if(!vlocityMap.isEmpty()) {
            packageXML += '    <!-- Vlocity Components -->\n';
            for(String type : vlocityMap.keySet()) {
                Set<String> members = vlocityMap.get(type);
                if(members == null || members.isEmpty()) continue;

                packageXML += '    <types>\n';
                for(String member : new List<String>(members)) {
                    packageXML += '        <members>' + member.escapeXml() + '</members>\n';
                }
                packageXML += '        <name>' + type.escapeXml() + '</name>\n';
                packageXML += '    </types>\n';
            }
        }

        packageXML += '    <version>58.0</version>\n</Package>';
        return packageXML;
    }

    /**
     * @description Saves the generated package.xml as both an Attachment and ContentVersion
     * @param packageXML The content of the package.xml file
     * @param userStoryID The ID of the User Story to attach the file to
     * @throws CustomException if the save operation fails
     */
    private static void savePackageXML(String packageXML, Id userStoryID) {
        if(String.isBlank(packageXML) || userStoryID == null) {
            throw new CustomException('Invalid package XML content or User Story ID');
        }

        try {
            // Create Attachment (for backward compatibility)
            Attachment att = new Attachment(
                Name = 'package.xml',
                Body = Blob.valueOf(packageXML),
                ContentType = 'text/xml',
                ParentId = userStoryID
            );
            insert att;

            // Save as ContentVersion for Lightning Experience
            ContentVersion newCV = new ContentVersion(
                Title = 'package.xml',
                PathOnClient = 'package.xml',
                VersionData = Blob.valueOf(packageXML),
                FirstPublishLocationId = userStoryID
            );
            insert newCV;
        } catch(Exception e) {
            throw new CustomException('Error saving package.xml: ' + e.getMessage());
        }
    }

    /**
     * @description Converts a string action to the corresponding CopadoOperation enum value
     * @param action The string representation of the action
     * @return CopadoOperation The corresponding enum value
     */
    private static CopadoOperation getCopadoOperation(String action) {
        if(String.isBlank(action)) return CopadoOperation.ADD_NEW;
        
        switch on action.toUpperCase() {
            when 'ADD' {
                return CopadoOperation.ADD_NEW;
            }
            when 'FULL' {
                return CopadoOperation.FULL_OP;
            }
            when 'DELETE' {
                return CopadoOperation.DEL_OP;
            }
            when 'RETRIEVEONLY' {
                return CopadoOperation.RETR_ONLY;
            }
            when 'SELECTIVECOMMIT' {
                return CopadoOperation.SEL_COMMIT;
            }
            when else {
                return CopadoOperation.ADD_NEW;
            }
        }
    }

    /**
     * @description Custom exception class for PackageXMLGenerator specific errors
     */
    public class CustomException extends Exception {}
}
