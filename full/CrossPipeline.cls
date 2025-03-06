public class CrossPipeline {
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
            /*// Create Attachment
            Attachment att = new Attachment(
                Name = 'package.xml',
                Body = Blob.valueOf(packageXML),
                ContentType = 'text/xml',
                ParentId = userStoryID
            );
            insert att;*/

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

    
    Public static void autoCommit(Id userStoryID){
                
        ContentDocumentLink cl= [SELECT Id, LinkedEntityId, ContentDocumentId, Visibility, 
                                 ContentDocument.Title, ContentDocument.createdDate, 
                                 ContentDocument.FileType 
                                 FROM ContentDocumentLink 
                                 WHERE LinkedEntityId = :userStoryID
                                 AND ContentDocument.Title LIKE 'package%'
                                 AND ContentDocument.FileExtension = 'xml'
                                 LIMIT 1 ];
        ContentVersion cv     =    [SELECT Checksum,ContentBodyId,
                                ContentDocumentId,ContentLocation,
                                Title,VersionData,VersionNumber
                                FROM ContentVersion WHERE ContentDocumentId =:cl.ContentDocumentId];
        blob b = cv.VersionData;
        String xmlContent = EncodingUtil.base64Decode(EncodingUtil.base64Encode(b)).toString();
        
        List<copado.CommitAction.Change> changes = new List<copado.CommitAction.Change>();
            
        Dom.Document doc = new Dom.Document();
        doc.load(xmlContent);
        Dom.XmlNode rootElement = doc.getRootElement();
        List<Dom.XmlNode> metadataTypes = rootElement.getChildElements();
        // Set of Vlocity metadata types
        Set<String> vlocityTypes = new Set<String>{
            'OmniScript',
                'DataRaptor',
                'IntegrationProcedure',
                'VlocityCard',
                'VlocityUITemplate','FlexCard'
                // Add other Vlocity metadata types as needed
                };
        for (Dom.XmlNode metadataType : metadataTypes) {
            if (metadataType.getName() == 'types') {
                String metadataTypeName = metadataType.getChildElement('name', 'http://soap.sforce.com/2006/04/metadata').getText();
                System.debug('Metadata Type: ' + metadataTypeName);
                List<Dom.XmlNode> metadataMembers = metadataType.getChildElements();
                for (Dom.XmlNode metadataMember : metadataMembers) {
                    if (metadataMember.getName() == 'members') {
                        copado.CommitAction.Change change = new copado.CommitAction.Change();
                        change.a = 'Add';
                        change.n = metadataMember.getText();
                        change.t = metadataTypeName;
                        
                        // Add context based on metadata type
                        if (vlocityTypes.contains(metadataTypeName)) {
                            change.c = 'Vlocity';
                            // Create JSON string for Vlocity metadata
                            Map<String, String> jsonDataMap = new Map<String, String>{
                                'vk' => metadataTypeName + '/' + change.n
                            };
                            change.j = JSON.serialize(jsonDataMap);
                        } else {
                            change.c = 'SFDX';
                        }
                        
                        System.debug('Metadata Entry: ' + change);
                        changes.add(change);
                    }
                }
            }
        }
        
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
    
    public static void deleteUserStoryAttachments(String userStoryId) {
        try {
            if(String.isBlank(userStoryId)) {
                throw new CustomException('User Story ID cannot be null or empty');
            }
    
            // Query for ContentDocumentLinks related to the User Story
            List<ContentDocumentLink> contentLinks = [
                SELECT Id, ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :userStoryId
            ];
    
            if(contentLinks.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'No attachments found for User Story: ' + userStoryId);
                return;
            }
    
            // Collect ContentDocument IDs to delete
            Set<Id> contentDocumentsToDelete = new Set<Id>();
            
            for(ContentDocumentLink cdl : contentLinks) {
                // Skip Copado Promotion changes files
                if(cdl.ContentDocument.Title.startsWith('Copado Promotion changes')) {
                    continue;
                }
                contentDocumentsToDelete.add(cdl.ContentDocumentId);
            }
    
            // Delete ContentDocuments if any found
            if(!contentDocumentsToDelete.isEmpty()) {
                // Query and delete classic Attachments
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
   

    public class CustomException extends Exception {}
}
