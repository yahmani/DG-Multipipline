public class PackageXMLGenerator {
    // Enum for Copado operations
    public enum CopadoOperation {
        ADD_NEW,
        FULL_OP,
        DEL_OP,
        RETR_ONLY,
        SEL_COMMIT
    }
    
    public static void generatePackageXML(String userStoryID) {
        try {
            if(String.isBlank(userStoryID)) {
                throw new CustomException('User Story ID cannot be null or empty');
            }

            // Query for the JSON file
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

            // Map to store metadata types and their members
            Map<String, Set<String>> metadataMap = new Map<String, Set<String>>();
            Map<String, Set<String>> vlocityMap = new Map<String, Set<String>>();
            // Map to store deleted components
            Map<String, Set<String>> deletedComponents = new Map<String, Set<String>>();

            for(ContentDocumentLink cdl : clList) {
                // Query ContentVersion
                List<ContentVersion> cvList = [SELECT VersionData 
                                             FROM ContentVersion 
                                             WHERE ContentDocumentId = :cdl.ContentDocumentId 
                                             AND IsLatest = true 
                                             LIMIT 1];
                
                if(cvList.isEmpty()) {
                    continue;
                }

                // Parse JSON content
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

            // Remove deleted components from metadata map
            removeDeletedComponents(metadataMap, deletedComponents);

            if(metadataMap.isEmpty() && vlocityMap.isEmpty()) {
                throw new CustomException('No valid metadata found to process');
            }

            // Generate and save package.xml
            String packageXML = generatePackageXMLContent(metadataMap, vlocityMap);
            savePackageXML(packageXML, userStoryID);

            System.debug(LoggingLevel.INFO, 'Successfully generated package.xml');

        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating package.xml: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }

    private static void processChanges(List<Object> changes, 
                                     Map<String, Set<String>> metadataMap, 
                                     Map<String, Set<String>> vlocityMap,
                                     Map<String, Set<String>> deletedComponents) {
        for(Object changeObj : changes) {
            if(changeObj == null) continue;

            Map<String, Object> change = (Map<String, Object>)changeObj;
            if(change == null || change.isEmpty()) continue;

            String action = (String)change.get('a');
            String type = (String)change.get('t');
            String name = (String)change.get('n');

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

            // Skip RetrieveOnly components
            if(operation == CopadoOperation.RETR_ONLY) {
                continue;
            }

            // Process Vlocity or standard components
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

    private static void processVlocityComponent(Map<String, Object> change, 
                                              String name, 
                                              Map<String, Set<String>> vlocityMap, 
                                              CopadoOperation operation) {
        try {
            String jsonStr = (String)change.get('j');
            if(String.isBlank(jsonStr)) return;

            Map<String, Object> vlocityData = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            if(vlocityData == null || !vlocityData.containsKey('vk')) return;

            String vlocityKey = (String)vlocityData.get('vk');
            if(String.isBlank(vlocityKey)) return;

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

        // Add Vlocity types if present
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

    private static void savePackageXML(String packageXML, Id userStoryID) {
        if(String.isBlank(packageXML) || userStoryID == null) {
            throw new CustomException('Invalid package XML content or User Story ID');
        }

        try {
            // Create Attachment
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

    public class CustomException extends Exception {}
}
