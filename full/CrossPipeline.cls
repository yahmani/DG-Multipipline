/**
 * @description CrossPipeline class handles cross-org deployment operations in Copado
 * It manages package.xml generation, metadata commits, and user story attachment cleanup
 */
public class CrossPipeline {
    /**
     * @description Enum defining the different types of operations that can be performed during deployment
     * These operations determine how metadata changes are handled in the pipeline
     */
    public enum CopadoOperation {
        ADD_NEW,        // For new components being added
        FULL_OP,        // For full operations (typically updates)
        DEL_OP,         // For component deletions
        RETR_ONLY,      // For components that should only be retrieved
        SEL_COMMIT      // For selective commit operations
    }

    /**
     * @description Generates a package.xml file from promotion changes in a User Story
     * This method processes both standard Salesforce metadata and Vlocity components
     * @param userStoryID The ID of the User Story containing the changes
     * @throws CustomException if the process fails
     */
    static void generatePackageXML(String userStoryID) {
        try {
            if(String.isBlank(userStoryID)) {
                throw new CustomException('User Story ID cannot be null or empty');
            }

            // Query for Copado Promotion changes JSON files
            // These files contain the metadata changes that need to be processed
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

            // Initialize maps to track different types of components
            Map<String, Set<String>> metadataMap = new Map<String, Set<String>>();      // Standard Salesforce metadata
            Map<String, Set<String>> vlocityMap = new Map<String, Set<String>>();       // Vlocity-specific components
            Map<String, Set<String>> deletedComponents = new Map<String, Set<String>>(); // Components marked for deletion

            // Process each JSON file containing changes
            for(ContentDocumentLink cdl : clList) {
                // Get the latest version of each file
                List<ContentVersion> cvList = [SELECT VersionData 
                                              FROM ContentVersion 
                                              WHERE ContentDocumentId = :cdl.ContentDocumentId 
                                              AND IsLatest = true 
                                              LIMIT 1];
                
                if(cvList.isEmpty()) continue;

                // Parse the JSON content
                String jsonContent = cvList[0].VersionData.toString();
                if(String.isBlank(jsonContent)) continue;

                try {
                    List<Object> changes = (List<Object>)JSON.deserializeUntyped(jsonContent);
                    if(changes == null || changes.isEmpty()) continue;

                    // Process the changes and categorize them
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
     * @description Processes metadata changes from the JSON content
     * Categorizes changes into standard metadata, Vlocity components, and deletions
     * @param changes List of change objects from the JSON
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

            // Extract change details
            String action = (String)change.get('a');  // Action type (Add, Delete, etc.)
            String type = (String)change.get('t');    // Metadata type
            String name = (String)change.get('n');    // Component name

            if(String.isBlank(action) || String.isBlank(type) || String.isBlank(name)) continue;

            CopadoOperation operation = getCopadoOperation(action);

            // Handle deleted components
            if(operation == CopadoOperation.DEL_OP) {
                if(!deletedComponents.containsKey(type)) {
                    deletedComponents.put(type, new Set<String>());
                }
                deletedComponents.get(type).add(name);
                continue;
            }

            // Skip components marked for retrieve only
            if(operation == CopadoOperation.RETR_ONLY) continue;

            // Process either Vlocity or standard components
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
     * Ensures deleted components don't appear in the final package.xml
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
     * @description Processes Vlocity-specific components and their metadata
     * Handles the special structure and requirements of Vlocity components
     * @param change The change object containing Vlocity data
     * @param name Component name
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
     * @description Generates the XML content for the package.xml file
     * Includes both standard metadata and Vlocity components
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
     * @description Saves the generated package.xml file as a ContentVersion
     * @param packageXML The content of the package.xml file
     * @param userStoryID The ID of the User Story to attach the file to
     * @throws CustomException if the save operation fails
     */
    private static void savePackageXML(String packageXML, Id userStoryID) {
        if(String.isBlank(packageXML) || userStoryID == null) {
            throw new CustomException('Invalid package XML content or User Story ID');
        }

        try {
            // Note: Classic Attachment creation is commented out but kept for reference
            /*// Create Attachment
            Attachment att = new Attachment(
                Name = 'package.xml',
                Body = Blob.valueOf(packageXML),
                ContentType = 'text/xml',
                ParentId = userStoryID
            );
            insert att;*/

            // Save as ContentVersion for Lightning Experience compatibility
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
     * @description Automatically commits changes to the repository based on package.xml content
     * Creates a commit request with all components listed in the package.xml
     * @param userStoryID The ID of the User Story containing the package.xml
     */
    Public static void autoCommit(Id userStoryID) {
        // Find the latest package.xml file
        ContentDocumentLink cl = [SELECT Id, LinkedEntityId, ContentDocumentId, Visibility, 
                                  ContentDocument.Title, ContentDocument.createdDate, 
                                  ContentDocument.FileType 
                                  FROM ContentDocumentLink 
                                  WHERE LinkedEntityId = :userStoryID
                                  AND ContentDocument.Title LIKE 'package%'
                                  AND ContentDocument.FileExtension = 'xml'
                                  LIMIT 1 ];
        
        // Get the content of package.xml
        ContentVersion cv = [SELECT Checksum, ContentBodyId,
                                 ContentDocumentId, ContentLocation,
                                 Title, VersionData, VersionNumber
                                 FROM ContentVersion 
                                 WHERE ContentDocumentId = :cl.ContentDocumentId];
        
        blob b = cv.VersionData;
        String xmlContent = EncodingUtil.base64Decode(EncodingUtil.base64Encode(b)).toString();
        
        // Prepare list for commit changes
        List<copado.CommitAction.Change> changes = new List<copado.CommitAction.Change>();
            
        // Parse package.xml content
        Dom.Document doc = new Dom.Document();
        doc.load(xmlContent);
        Dom.XmlNode rootElement = doc.getRootElement();
        List<Dom.XmlNode> metadataTypes = rootElement.getChildElements();
        
        // Define Vlocity metadata types for special handling
        Set<String> vlocityTypes = new Set<String>{
            'OmniScript',
            'DataRaptor',
            'IntegrationProcedure',
            'VlocityCard',
            'VlocityUITemplate',
            'FlexCard'
        };
        
        // Process each metadata type in the package.xml
        for (Dom.XmlNode metadataType : metadataTypes) {
            if (metadataType.getName() == 'types') {
                String metadataTypeName = metadataType.getChildElement('name', 'http://soap.sforce.com/2006/04/metadata').getText();
                List<Dom.XmlNode> metadataMembers = metadataType.getChildElements();
                
                // Create commit change for each component
                for (Dom.XmlNode metadataMember : metadataMembers) {
                    if (metadataMember.getName() == 'members') {
                        copado.CommitAction.Change change = new copado.CommitAction.Change();
                        change.a = 'Add';
                        change.n = metadataMember.getText();
                        change.t = metadataTypeName;
                        
                        // Set context based on whether it's a Vlocity component
                        if (vlocityTypes.contains(metadataTypeName)) {
                            change.c = 'Vlocity';
                            Map<String, String> jsonDataMap = new Map<String, String>{
                                'vk' => metadataTypeName + '/' + change.n
                            };
                            change.j = JSON.serialize(jsonDataMap);
                        } else {
                            change.c = 'SFDX';
                        }
                        
                        changes.add(change);
                    }
                }
            }
        }
        
        // Create and execute the commit request
        copado.CommitAction.Request request = new copado.CommitAction.Request();
        request.userStoryId = userStoryId;
        request.changes = changes;
        request.commitId = '';
        request.message = 'Automated commit';
        request.baseBranch = 'main';
        request.recreateFeatureBranch = true;
        request.executeCommit = true;
        copado.CommitAction.commitChanges(new List<copado.CommitAction.Request> {request});
    }

    /**
     * @description Deletes attachments from a User Story except for Copado Promotion changes
     * Handles both classic Attachments and ContentDocument (Files) records
     * @param userStoryId The ID of the User Story to clean up
     * @throws CustomException if the deletion process fails
     */
    public static void deleteUserStoryAttachments(String userStoryId) {
        try {
            if(String.isBlank(userStoryId)) {
                throw new CustomException('User Story ID cannot be null or empty');
            }
    
            // Query for all files linked to the User Story
            List<ContentDocumentLink> contentLinks = [
                SELECT Id, ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :userStoryId
            ];
    
            if(contentLinks.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'No attachments found for User Story: ' + userStoryId);
                return;
            }
    
            // Collect files to delete, excluding Copado Promotion changes
            Set<Id> contentDocumentsToDelete = new Set<Id>();
            for(ContentDocumentLink cdl : contentLinks) {
                if(cdl.ContentDocument.Title.startsWith('Copado Promotion changes')) {
                    continue;
                }
                contentDocumentsToDelete.add(cdl.ContentDocumentId);
            }
    
            if(!contentDocumentsToDelete.isEmpty()) {
                // Delete classic attachments
                List<Attachment> attachmentsToDelete = [
                    SELECT Id 
                    FROM Attachment 
                    WHERE ParentId = :userStoryId
                    AND Name != 'Copado Promotion changes.json'
                ];
                
                if(!attachmentsToDelete.isEmpty()) {
                    delete attachmentsToDelete;
                    System.debug(LoggingLevel.INFO, 'Deleted ' + attachmentsToDelete.size() + ' classic attachments');
                }
    
                // Delete Files (ContentDocuments)
                List<ContentDocument> documentsToDelete = [
                    SELECT Id 
                    FROM ContentDocument 
                    WHERE Id IN :contentDocumentsToDelete
                ];
                
                if(!documentsToDelete.isEmpty()) {
                    delete documentsToDelete;
                    System.debug(LoggingLevel.INFO, 'Deleted ' + documentsToDelete.size() + ' files');
                }
            }
    
            System.debug(LoggingLevel.INFO, 'Successfully processed attachments for User Story: ' + userStoryId);
    
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error deleting attachments: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw new CustomException('Error deleting attachments: ' + e.getMessage());
        }
    }

    /**
     * @description Custom exception class for CrossPipeline specific errors
     */
    public class CustomException extends Exception {}
}
