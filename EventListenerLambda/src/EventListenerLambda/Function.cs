using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
using Amazon.Runtime.Internal.Util;
using EventListenerLambda.Models;
using EventListenerLambda.Startup;
using Microsoft.Extensions.DependencyInjection;


// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace EventListenerLambda;

public class Function
{
    private readonly IDynamoDBContext _dynamoDbContext;
    private const string DynamoDbTable = "event_storage";
    
    public Function(): this(DependencyInjection.BuildServiceProvider())
    {
    }

    public Function(IServiceProvider services)
    {
        _dynamoDbContext = services.GetRequiredService<IDynamoDBContext>();
    }
    
    /// <summary>
    /// This method is called for every Lambda invocation. This method takes in an SQS event object and can be used 
    /// to respond to SQS messages.
    /// </summary>
    /// <param name="evnt"></param>
    /// <param name="context"></param>
    /// <returns></returns>
    public async Task FunctionHandler(SQSEvent evnt, ILambdaContext context)
    {
        try
        {
            foreach (var message in evnt.Records)
            {
                await ProcessMessageAsync(message, context);
            }
        }
        catch (Exception ex)
        {
            context.Logger.LogError($"Error message: {ex.Message}. StackTrace: {ex.StackTrace}");
            throw;
        }
    }

    private async Task ProcessMessageAsync(SQSEvent.SQSMessage message, ILambdaContext context)
    {
        context.Logger.LogInformation($"Processing message {message.Body}");

        await _dynamoDbContext.SaveAsync(new DynamoDbItem(Guid.NewGuid().ToString(), message.Body), new DynamoDBOperationConfig
        {
            OverrideTableName = DynamoDbTable,
            ConsistentRead = true
        });
        
        context.Logger.LogInformation("Message Processed :)");
    }
}