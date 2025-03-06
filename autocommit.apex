
Id userStoryID = 'a1vfI0000008TxhQAE';

ContentDocumentLink cl= [SELECT Id, LinkedEntityId, ContentDocumentId, Visibility, 
                         ContentDocument.Title, ContentDocument.createdDate, 
                                     ContentDocument.FileType FROM ContentDocumentLink WHERE LinkedEntityId = :userStoryID];
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
