/**
 * @description Test class for PackageXMLGenerator which tests the generation of package.xml files
 * from Copado promotion changes
 */
@IsTest
private class PackageXMLGeneratorTest {
    
    /**
     * @description Sets up test data that will be used across all test methods
     * Creates a User Story and sample JSON files for both standard and Vlocity metadata
     */
    @TestSetup
    static void setupTestData() {
        // Create a User Story record as the parent for our test data
        copado__User_Story__c userStory = new copado__User_Story__c(
            Name = 'Test User Story'
        );
        insert userStory;
        
        // Create JSON that simulates standard Salesforce metadata changes
        // This JSON includes both an addition (TestClass) and a deletion (Test__c)
        String standardJson = '[{' +
            '"a": "ADD",' +  // 'a' represents action
            '"t": "ApexClass",' +  // 't' represents type
            '"n": "TestClass"' +   // 'n' represents name
            '}, {' +
            '"a": "DELETE",' +
            '"t": "CustomObject",' +
            '"n": "Test__c"' +
            '}]';
            
        // Create JSON that simulates Vlocity metadata changes
        // The 'j' field contains Vlocity-specific information including the vlocity key (vk)
        String vlocityJson = '[{' +
            '"a": "ADD",' +
            '"t": "VlocityType",' +
            '"n": "VlocityTest",' +
            '"j": "{' +
            '    \\"vk\\": \\"DataRaptor/TestDR\\"' +  // vk represents the Vlocity key
            '}"' +
            '}]';
            
        // Create ContentVersion record for standard metadata changes
        ContentVersion standardCV = new ContentVersion(
            Title = 'Copado Promotion changes_1',  // Title must match the pattern expected by PackageXMLGenerator
            PathOnClient = 'changes1.json',
            VersionData = Blob.valueOf(standardJson),
            FirstPublishLocationId = userStory.Id
        );
        insert standardCV;
        
        // Create ContentVersion record for Vlocity metadata changes
        ContentVersion vlocityCV = new ContentVersion(
            Title = 'Copado Promotion changes_2',
            PathOnClient = 'changes2.json',
            VersionData = Blob.valueOf(vlocityJson),
            FirstPublishLocationId = userStory.Id
        );
        insert vlocityCV;
    }
    
    /**
     * @description Tests the generation of package.xml with standard Salesforce metadata
     * Verifies that added components are included and deleted components are excluded
     */
    @IsTest
    static void testGeneratePackageXMLWithStandardMetadata() {
        copado__User_Story__c userStory = [SELECT Id FROM copado__User_Story__c LIMIT 1];
        
        Test.startTest();
        PackageXMLGenerator.generatePackageXML(userStory.Id);
        Test.stopTest();
        
        // Query the generated package.xml file
        List<ContentVersion> resultCV = [
            SELECT Id, Title, VersionData 
            FROM ContentVersion 
            WHERE Title = 'package.xml' 
            AND FirstPublishLocationId = :userStory.Id
        ];
        
        System.assertEquals(1, resultCV.size(), 'Package.xml should be created');
        String packageContent = resultCV[0].VersionData.toString();
        
        // Verify the package.xml contains the expected components
        System.assert(packageContent.contains('<members>TestClass</members>'), 'Package should contain TestClass');
        System.assert(packageContent.contains('<name>ApexClass</name>'), 'Package should contain ApexClass type');
        System.assert(!packageContent.contains('Test__c'), 'Package should not contain deleted component');
    }
    
    /**
     * @description Tests the generation of package.xml with Vlocity metadata
     * Verifies that Vlocity components are properly included in the package
     */
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
        // Verify Vlocity-specific content
        System.assert(packageContent.contains('<!-- Vlocity Components -->'), 'Package should contain Vlocity section');
        System.assert(packageContent.contains('<members>VlocityTest</members>'), 'Package should contain Vlocity component');
    }
    
    /**
     * @description Tests error handling when null User Story ID is provided
     * Verifies that appropriate exception is thrown
     */
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
    
    /**
     * @description Tests scenario where User Story has no associated changes
     * Verifies that appropriate exception is thrown
     */
    @IsTest
    static void testGeneratePackageXMLWithNoChanges() {
        // Create a User Story with no associated changes
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
    
    /**
     * @description Tests handling of invalid JSON content
     * Verifies that the class can handle malformed JSON without failing
     * and still process valid content
     */
    @IsTest
    static void testGeneratePackageXMLWithInvalidJSON() {
        copado__User_Story__c userStory = [SELECT Id FROM copado__User_Story__c LIMIT 1];
        
        // Create a ContentVersion with invalid JSON
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
        
        // Verify that package.xml is still created (from valid JSON files)
        List<ContentVersion> resultCV = [
            SELECT Id 
            FROM ContentVersion 
            WHERE Title = 'package.xml' 
            AND FirstPublishLocationId = :userStory.Id
        ];
        System.assertEquals(1, resultCV.size(), 'Package.xml should be created despite invalid JSON');
    }
}
