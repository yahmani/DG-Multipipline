/**
 * @description Test class for CrossPipeline functionality
 * Covers package.xml generation, auto-commit, and attachment management
 */
@IsTest
private class CrossPipelineTest {
    
    /**
     * @description Sets up test data common to multiple test methods
     * @return Id Returns the ID of the created User Story
     */
    private static Id setupTestData() {
        // Create a User Story record
        copado__User_Story__c userStory = new copado__User_Story__c(
            Name = 'Test Story',
            copado__Status__c = 'Draft'
        );
        insert userStory;
        
        return userStory.Id;
    }
    
    /**
     * @description Creates a test JSON file with metadata changes
     * @param userStoryId The ID of the User Story to attach the file to
     * @return ContentVersion The created ContentVersion record
     */
    private static ContentVersion createTestJsonFile(Id userStoryId) {
        // Create sample JSON content for metadata changes
        List<Map<String, Object>> changes = new List<Map<String, Object>>();
        
        // Add a standard component
        changes.add(new Map<String, Object>{
            'a' => 'ADD',
            't' => 'ApexClass',
            'n' => 'TestClass'
        });
        
        // Add a Vlocity component
        Map<String, Object> vlocityComponent = new Map<String, Object>{
            'a' => 'ADD',
            't' => 'VlocityComponent',
            'n' => 'TestVlocityComponent',
            'j' => JSON.serialize(new Map<String, String>{
                'vk' => 'OmniScript/Test_Script'
            })
        };
        changes.add(vlocityComponent);
        
        // Create ContentVersion record
        ContentVersion cv = new ContentVersion(
            Title = 'Copado Promotion changes',
            PathOnClient = 'Copado Promotion changes.json',
            VersionData = Blob.valueOf(JSON.serialize(changes)),
            FirstPublishLocationId = userStoryId
        );
        insert cv;
        
        return cv;
    }
    
    /**
     * @description Tests the generation of package.xml from metadata changes
     */
    @IsTest
    static void testGeneratePackageXML() {
        // Setup test data
        Id userStoryId = setupTestData();
        createTestJsonFile(userStoryId);
        
        Test.startTest();
        
        // Execute the package.xml generation
        CrossPipeline.generatePackageXML(userStoryId);
        
        Test.stopTest();
        
        // Verify the package.xml was created
        List<ContentDocumentLink> packageFiles = [
            SELECT ContentDocument.Title 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :userStoryId 
            AND ContentDocument.Title = 'package.xml'
        ];
        
        System.assertEquals(1, packageFiles.size(), 'Package.xml file should be created');
    }
    
    /**
     * @description Tests the handling of deleted components in package.xml generation
     */
    @IsTest
    static void testDeletedComponents() {
        Id userStoryId = setupTestData();
        
        // Create JSON with deleted components
        List<Map<String, Object>> changes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'a' => 'DELETE',
                't' => 'ApexClass',
                'n' => 'DeletedClass'
            },
            new Map<String, Object>{
                'a' => 'ADD',
                't' => 'ApexClass',
                'n' => 'DeletedClass'
            }
        };
        
        ContentVersion cv = new ContentVersion(
            Title = 'Copado Promotion changes',
            PathOnClient = 'Copado Promotion changes.json',
            VersionData = Blob.valueOf(JSON.serialize(changes)),
            FirstPublishLocationId = userStoryId
        );
        insert cv;
        
        Test.startTest();
        CrossPipeline.generatePackageXML(userStoryId);
        Test.stopTest();
        
        // Verify the deleted component is not in package.xml
        List<ContentVersion> packageXml = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE FirstPublishLocationId = :userStoryId 
            AND Title = 'package.xml'
        ];
        
        String packageContent = packageXml[0].VersionData.toString();
        System.assert(!packageContent.contains('DeletedClass'), 
            'Deleted component should not appear in package.xml');
    }
    
    /**
     * @description Tests the auto-commit functionality
     */
    @IsTest
    static void testAutoCommit() {
        Id userStoryId = setupTestData();
        
        // Create a package.xml file
        String packageXml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
            '<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
            '    <types>\n' +
            '        <members>TestClass</members>\n' +
            '        <name>ApexClass</name>\n' +
            '    </types>\n' +
            '    <version>58.0</version>\n' +
            '</Package>';
        
        ContentVersion cv = new ContentVersion(
            Title = 'package.xml',
            PathOnClient = 'package.xml',
            VersionData = Blob.valueOf(packageXml),
            FirstPublishLocationId = userStoryId
        );
        insert cv;
        
        Test.startTest();
        CrossPipeline.autoCommit(userStoryId);
        Test.stopTest();
        
        // Verification would depend on Copado's commit functionality
        // Add appropriate assertions based on your implementation
    }
    
    /**
     * @description Tests the deletion of User Story attachments
     */
    @IsTest
    static void testDeleteUserStoryAttachments() {
        Id userStoryId = setupTestData();
        
        // Create test attachments
        Attachment testAtt = new Attachment(
            Name = 'Test.txt',
            Body = Blob.valueOf('Test Content'),
            ParentId = userStoryId
        );
        insert testAtt;
        
        // Create test ContentVersion
        ContentVersion testCV = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('Test Content'),
            FirstPublishLocationId = userStoryId
        );
        insert testCV;
        
        // Create Copado Promotion changes file (should not be deleted)
        ContentVersion copadoCV = new ContentVersion(
            Title = 'Copado Promotion changes',
            PathOnClient = 'Copado Promotion changes.json',
            VersionData = Blob.valueOf('{"changes": []}'),
            FirstPublishLocationId = userStoryId
        );
        insert copadoCV;
        
        Test.startTest();
        CrossPipeline.deleteUserStoryAttachments(userStoryId);
        Test.stopTest();
        
        // Verify results
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
    
    /**
     * @description Tests error handling for invalid inputs
     */
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
    
    /**
     * @description Tests processing of Vlocity components
     */
    @IsTest
    static void testVlocityComponentProcessing() {
        Id userStoryId = setupTestData();
        
        // Create JSON with Vlocity component
        List<Map<String, Object>> changes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'a' => 'ADD',
                't' => 'VlocityComponent',
                'n' => 'TestVlocityComponent',
                'j' => JSON.serialize(new Map<String, String>{
                    'vk' => 'OmniScript/Test_Script'
                })
            }
        };
        
        ContentVersion cv = new ContentVersion(
            Title = 'Copado Promotion changes',
            PathOnClient = 'Copado Promotion changes.json',
            VersionData = Blob.valueOf(JSON.serialize(changes)),
            FirstPublishLocationId = userStoryId
        );
        insert cv;
        
        Test.startTest();
        CrossPipeline.generatePackageXML(userStoryId);
        Test.stopTest();
        
        // Verify Vlocity component in package.xml
        List<ContentVersion> packageXml = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE FirstPublishLocationId = :userStoryId 
            AND Title = 'package.xml'
        ];
        
        String packageContent = packageXml[0].VersionData.toString();
        System.assert(packageContent.contains('OmniScript'), 
            'Vlocity component should be included in package.xml');
    }
    
    /**
     * @description Tests handling of invalid JSON content
     */
    @IsTest
    static void testInvalidJsonHandling() {
        Id userStoryId = setupTestData();
        
        // Create invalid JSON content
        ContentVersion cv = new ContentVersion(
            Title = 'Copado Promotion changes',
            PathOnClient = 'Copado Promotion changes.json',
            VersionData = Blob.valueOf('Invalid JSON Content'),
            FirstPublishLocationId = userStoryId
        );
        insert cv;
        
        Test.startTest();
        try {
            CrossPipeline.generatePackageXML(userStoryId);
            System.assert(false, 'Should throw an exception for invalid JSON');
        } catch(Exception e) {
            System.assert(e.getMessage().contains('No valid metadata found'),
                'Should handle invalid JSON appropriately');
        }
        Test.stopTest();
    }
}
