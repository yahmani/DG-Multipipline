@IsTest
private class CrossPipelineTest {
    
    @TestSetup
    static void setupTestData() {
        copado__User_Story__c userStory = new copado__User_Story__c(
            Name = 'Test Story',
            copado__Status__c = 'Draft'
        );
        insert userStory;
    }
    
    private static Id getTestUserStoryId() {
        return [SELECT Id FROM copado__User_Story__c LIMIT 1].Id;
    }
    
    private static ContentVersion createContentVersion(String title, String content, Boolean isJson) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + (isJson ? '.json' : '.xml'),
            VersionData = Blob.valueOf(content),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }
    
    private static void linkContentToUserStory(Id contentDocumentId, Id userStoryId) {
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = userStoryId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
    }
    
    private static ContentVersion createTestJsonFile(Id userStoryId, String operation) {
        List<Map<String, Object>> changes = new List<Map<String, Object>>();
        
        // Add operation-specific components
        if(operation == 'FULL') {
            changes.add(new Map<String, Object>{
                'a' => 'FULL',
                't' => 'ApexClass',
                'n' => 'TestFullClass'
            });
        } else if(operation == 'RETRIEVEONLY') {
            changes.add(new Map<String, Object>{
                'a' => 'RETRIEVEONLY',
                't' => 'ApexClass',
                'n' => 'TestRetrieveClass'
            });
        } else if(operation == 'SELECTIVECOMMIT') {
            changes.add(new Map<String, Object>{
                'a' => 'SELECTIVECOMMIT',
                't' => 'ApexClass',
                'n' => 'TestSelectiveClass'
            });
        }
        
        // Add standard component
        changes.add(new Map<String, Object>{
            'a' => 'ADD',
            't' => 'ApexClass',
            'n' => 'TestClass'
        });
        
        // Add Vlocity component
        changes.add(new Map<String, Object>{
            'a' => 'ADD',
            't' => 'OmniScript',
            'n' => 'TestOmniScript',
            'j' => JSON.serialize(new Map<String, String>{
                'vk' => 'OmniScript/Test_Script'
            })
        });
        
        ContentVersion cv = createContentVersion(
            'Copado Promotion changes',
            JSON.serialize(changes),
            true
        );
        linkContentToUserStory(cv.ContentDocumentId, userStoryId);
        return cv;
    }
    
    @IsTest
    static void testGeneratePackageXML() {
        Id userStoryId = getTestUserStoryId();
        createTestJsonFile(userStoryId, 'ADD');
        
        Test.startTest();
        CrossPipeline.generatePackageXML(userStoryId);
        Test.stopTest();
        
        List<ContentVersion> packageXml = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE Title = 'package.xml'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        System.assertEquals(1, packageXml.size(), 'Package.xml file should be created');
        String packageContent = packageXml[0].VersionData.toString();
        System.assert(packageContent.contains('ApexClass'), 'Package.xml should contain ApexClass type');
        System.assert(packageContent.contains('TestClass'), 'Package.xml should contain TestClass member');
    }
    
    @IsTest
    static void testDeletedComponents() {
        Id userStoryId = getTestUserStoryId();
        
        List<Map<String, Object>> changes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'a' => 'DELETE',
                't' => 'ApexClass',
                'n' => 'DeletedClass'
            },
            new Map<String, Object>{
                'a' => 'ADD',
                't' => 'ApexClass',
                'n' => 'ActiveClass'
            }
        };
        
        ContentVersion cv = createContentVersion(
            'Copado Promotion changes',
            JSON.serialize(changes),
            true
        );
        linkContentToUserStory(cv.ContentDocumentId, userStoryId);
        
        Test.startTest();
        CrossPipeline.generatePackageXML(userStoryId);
        Test.stopTest();
        
        List<ContentVersion> packageXml = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE Title = 'package.xml'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        String packageContent = packageXml[0].VersionData.toString();
        System.assert(packageContent.contains('ActiveClass'), 'Active component should be in package.xml');
        System.assert(!packageContent.contains('DeletedClass'), 'Deleted component should not be in package.xml');
    }
    
    @IsTest
    static void testAutoCommit() {
        Id userStoryId = getTestUserStoryId();
        
        String packageXml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
            '<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
            '    <types>\n' +
            '        <members>TestClass</members>\n' +
            '        <name>ApexClass</name>\n' +
            '    </types>\n' +
            '    <version>58.0</version>\n' +
            '</Package>';
        
        ContentVersion cv = createContentVersion('package', packageXml, false);
        linkContentToUserStory(cv.ContentDocumentId, userStoryId);
        
        Test.startTest();
        try {
            CrossPipeline.autoCommit(userStoryId);
            System.assert(false, 'Should throw a license exception');
        } catch(Exception e) {
            System.assert(e.getMessage().contains('license'), 
                'Should throw license-related exception');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testDeleteUserStoryAttachments() {
        Id userStoryId = getTestUserStoryId();
        
        // Create test attachment
        Attachment testAtt = new Attachment(
            Name = 'Test.txt',
            Body = Blob.valueOf('Test Content'),
            ParentId = userStoryId
        );
        insert testAtt;
        
        // Create test file
        ContentVersion testCV = createContentVersion('Test File', 'Test Content', false);
        linkContentToUserStory(testCV.ContentDocumentId, userStoryId);
        
        // Create Copado changes file
        ContentVersion copadoCV = createContentVersion(
            'Copado Promotion changes',
            '{"changes": []}',
            true
        );
        linkContentToUserStory(copadoCV.ContentDocumentId, userStoryId);
        
        Test.startTest();
        CrossPipeline.deleteUserStoryAttachments(userStoryId);
        Test.stopTest();
        
        List<Attachment> remainingAttachments = [SELECT Id FROM Attachment WHERE ParentId = :userStoryId];
        System.assertEquals(0, remainingAttachments.size(), 'All regular attachments should be deleted');
        
        List<ContentDocumentLink> remainingFiles = [
            SELECT ContentDocument.Title 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :userStoryId
        ];
        
        Integer copadoFilesCount = 0;
        for(ContentDocumentLink cdl : remainingFiles) {
            if(cdl.ContentDocument.Title.startsWith('Copado Promotion changes')) {
                copadoFilesCount++;
            }
        }
        
        System.assertEquals(1, copadoFilesCount, 'Copado Promotion changes file should be preserved');
    }
    
    @IsTest
    static void testErrorHandling() {
        Test.startTest();
        
        try {
            CrossPipeline.generatePackageXML(null);
            System.assert(false, 'Should throw an exception for null User Story ID');
        } catch(CrossPipeline.CustomException e) {
            System.assert(e.getMessage().contains('User Story ID cannot be null'),
                'Should throw appropriate error message');
        }
        
        try {
            CrossPipeline.deleteUserStoryAttachments(null);
            System.assert(false, 'Should throw an exception for null User Story ID');
        } catch(CrossPipeline.CustomException e) {
            System.assert(e.getMessage().contains('User Story ID cannot be null'),
                'Should throw appropriate error message');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testAllOperationTypes() {
        Id userStoryId = getTestUserStoryId();
        
        Test.startTest();
        
        createTestJsonFile(userStoryId, 'FULL');
        CrossPipeline.generatePackageXML(userStoryId);
        
        createTestJsonFile(userStoryId, 'RETRIEVEONLY');
        CrossPipeline.generatePackageXML(userStoryId);
        
        createTestJsonFile(userStoryId, 'SELECTIVECOMMIT');
        CrossPipeline.generatePackageXML(userStoryId);
        
        Test.stopTest();
        
        List<ContentVersion> packageXmls = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE Title = 'package.xml'
            ORDER BY CreatedDate DESC
        ];
        
        System.assert(!packageXmls.isEmpty(), 'Package.xml files should be created');
    }
    
    @IsTest
    static void testInvalidJsonContent() {
        Id userStoryId = getTestUserStoryId();
        
        ContentVersion cv = createContentVersion(
            'Copado Promotion changes',
            'Invalid JSON Content',
            true
        );
        linkContentToUserStory(cv.ContentDocumentId, userStoryId);
        
        Test.startTest();
        try {
            CrossPipeline.generatePackageXML(userStoryId);
            System.assert(false, 'Should throw an exception for invalid JSON');
        } catch(Exception e) {
            System.assert(e.getMessage().contains('No valid metadata found'), 
                'Should throw appropriate error message');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testEmptyMetadataHandling() {
        Id userStoryId = getTestUserStoryId();
        
        ContentVersion cv = createContentVersion(
            'Copado Promotion changes',
            JSON.serialize(new List<Map<String, Object>>()),
            true
        );
        linkContentToUserStory(cv.ContentDocumentId, userStoryId);
        
        Test.startTest();
        try {
            CrossPipeline.generatePackageXML(userStoryId);
            System.assert(false, 'Should throw an exception for empty metadata');
        } catch(Exception e) {
            System.assert(e.getMessage().contains('No valid metadata found'), 
                'Should throw appropriate error message');
        }
        Test.stopTest();
    }
}
