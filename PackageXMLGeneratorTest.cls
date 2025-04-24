@IsTest
private class PackageXMLGeneratorTest {
    
    @TestSetup
    static void setupTestData() {
        // Create a User Story record (assuming it's a custom object)
        copado__User_Story__c userStory = new copado__User_Story__c(
            Name = 'Test User Story'
        );
        insert userStory;
        
        // Create test JSON content for standard metadata
        String standardJson = '[{' +
            '"a": "ADD",' +
            '"t": "ApexClass",' +
            '"n": "TestClass"' +
            '}, {' +
            '"a": "DELETE",' +
            '"t": "CustomObject",' +
            '"n": "Test__c"' +
            '}]';
            
        // Create test JSON content for Vlocity metadata
        String vlocityJson = '[{' +
            '"a": "ADD",' +
            '"t": "VlocityType",' +
            '"n": "VlocityTest",' +
            '"j": "{' +
            '    \\"vk\\": \\"DataRaptor/TestDR\\"' +
            '}"' +
            '}]';
            
        // Create ContentVersion records
        ContentVersion standardCV = new ContentVersion(
            Title = 'Copado Promotion changes_1',
            PathOnClient = 'changes1.json',
            VersionData = Blob.valueOf(standardJson),
            FirstPublishLocationId = userStory.Id
        );
        insert standardCV;
        
        ContentVersion vlocityCV = new ContentVersion(
            Title = 'Copado Promotion changes_2',
            PathOnClient = 'changes2.json',
            VersionData = Blob.valueOf(vlocityJson),
            FirstPublishLocationId = userStory.Id
        );
        insert vlocityCV;
    }
    
    @IsTest
    static void testGeneratePackageXMLWithStandardMetadata() {
        // Get the User Story Id
        copado__User_Story__c userStory = [SELECT Id FROM copado__User_Story__c LIMIT 1];
        
        Test.startTest();
        PackageXMLGenerator.generatePackageXML(userStory.Id);
        Test.stopTest();
        
        // Verify the package.xml was created
        List<ContentVersion> resultCV = [
            SELECT Id, Title, VersionData 
            FROM ContentVersion 
            WHERE Title = 'package.xml' 
            AND FirstPublishLocationId = :userStory.Id
        ];
        
        System.assertEquals(1, resultCV.size(), 'Package.xml should be created');
        String packageContent = resultCV[0].VersionData.toString();
        
        // Verify package content
        System.assert(packageContent.contains('<members>TestClass</members>'), 'Package should contain TestClass');
        System.assert(packageContent.contains('<name>ApexClass</name>'), 'Package should contain ApexClass type');
        System.assert(!packageContent.contains('Test__c'), 'Package should not contain deleted component');
    }
    
    @IsTest
    static void testGeneratePackageXMLWithVlocityMetadata() {
        copado__User_Story__c userStory = [SELECT Id FROM copado__User_Story__c LIMIT 1];
        
        Test.startTest();
        PackageXMLGenerator.generatePackageXML(userStory.Id);
        Test.stopTest();
        
        List<ContentVersion> resultCV = [
            SELECT Id, VersionData 
            FROM ContentVersion 
            WHERE Title = 'package.xml' 
            AND FirstPublishLocationId = :userStory.Id
        ];
        
        String packageContent = resultCV[0].VersionData.toString();
        System.assert(packageContent.contains('<!-- Vlocity Components -->'), 'Package should contain Vlocity section');
        System.assert(packageContent.contains('<members>VlocityTest</members>'), 'Package should contain Vlocity component');
    }
    
    @IsTest
    static void testGeneratePackageXMLWithInvalidUserStory() {
        Test.startTest();
        try {
            PackageXMLGenerator.generatePackageXML(null);
            System.assert(false, 'Should throw an exception');
        } catch(PackageXMLGenerator.CustomException e) {
            System.assertEquals('User Story ID cannot be null or empty', e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGeneratePackageXMLWithNoChanges() {
        copado__User_Story__c userStory = new copado__User_Story__c(
            Name = 'Empty User Story'
        );
        insert userStory;
        
        Test.startTest();
        try {
            PackageXMLGenerator.generatePackageXML(userStory.Id);
            System.assert(false, 'Should throw an exception');
        } catch(PackageXMLGenerator.CustomException e) {
            System.assertEquals('No promotion changes files found', e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGeneratePackageXMLWithInvalidJSON() {
        copado__User_Story__c userStory = [SELECT Id FROM copado__User_Story__c LIMIT 1];
        
        // Create invalid JSON content
        ContentVersion invalidCV = new ContentVersion(
            Title = 'Copado Promotion changes_3',
            PathOnClient = 'changes3.json',
            VersionData = Blob.valueOf('Invalid JSON Content'),
            FirstPublishLocationId = userStory.Id
        );
        insert invalidCV;
        
        Test.startTest();
        PackageXMLGenerator.generatePackageXML(userStory.Id);
        Test.stopTest();
        
        // Verify the package.xml was still created with valid content
        List<ContentVersion> resultCV = [
            SELECT Id 
            FROM ContentVersion 
            WHERE Title = 'package.xml' 
            AND FirstPublishLocationId = :userStory.Id
        ];
        System.assertEquals(1, resultCV.size(), 'Package.xml should be created despite invalid JSON');
    }
}

/**

*/
