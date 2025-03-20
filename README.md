<h1>Introduction </h1>
The CrossPipeline class is a utility class that enables cross-pipeline deployments in Copado. <br/>
This functionality allows teams to deploy metadata and configurations across different pipelines while maintaining data integrity and proper version control.

<h1>Usage Guide </h1> 

<h2>Preparation </h2> 
<ul>
  <li>Add the CrossPipeline class to you Copado org (Apex Test class is coming)</li>
  <li>Back-promote the stories to be cross deployed to shared box in the master pipeline</li>
  <li>Download the 'Copado Promotion changes,json' file from the promotion related tab</li>
  <li>create a new story for the detail pipeline with the detail credential</li>
  <li>Upload the 'Copado Promotion changes' file to the newly created user story</li>
</ul>
<h2>Execution </h2> 
<ul>
  <li>Execute the anonymous script from Developer Console's Execute Anonymous Window</li>
  <ul>
    <li>Specify the user story record id, example :  userStoryID = 'a1vfI0000008UFRQA2';</li>
    <li>To clean user story attachment run : CrossPipeline.deleteUserStoryAttachments(userStoryID); </li>
    <li>To generate the package.xml file run : CrossPipeline.generatePackageXML(userStoryID); </li>
    <li>To autocommit the changes : CrossPipeline.autoCommit(userStoryID); </li>
  </ul>
</ul>
