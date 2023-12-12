# AWS Terraform Project

## Spinning Up The Infrastrucure

After clonning the repository, set up your aws credentials in your credentials file and move to the iac folder 

`cd iac`

Then run the command 

`terraform apply`

After setting up the changes the console will ask for your confirmation. Type

`yes`

## Publishing And Fetching Events

Once the infrastructure is up and running, move to the EventListenerLambda folder

` cd ../EventListenerLambda/src/EventListenerLambda`

and run the command

` aws sns publish --topic-arn <topic-arn> --message file://event.txt`

replacing the <topic-arn> placeholder with the `event-sns` topic arn which can be find in your AWS console. 
This command will publish the event contained in the event.txt file into the event-sns topic. 

Almost instantly the event will be stored in the `event_storage` DynamoDB table. You can also see the logs in the `/aws/lambda/event-listener` CloudWatch log group. After some moments (it can take up to five minutes) the event will be available in the `cko-project-events-bucket` s3 bucket. 
To fetch it locally, run the command 

`aws s3 sync s3://cko-project-events-bucket/events/<YYYY>/<MM>/<DD> events`

replacing the placeholders with the current date information. This will create the events folder containing your event information. 

And Voilà, the event has travelled the world and come back to your machine intact :D
