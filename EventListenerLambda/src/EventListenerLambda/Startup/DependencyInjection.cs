using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Microsoft.Extensions.DependencyInjection;

namespace EventListenerLambda.Startup;

public static class DependencyInjection
{
    public static ServiceProvider BuildServiceProvider()
    {

        var services = new ServiceCollection();
        
        var config = new AmazonDynamoDBConfig();
        config.AuthenticationRegion = "eu-west-1";
        
        var client = new AmazonDynamoDBClient(config);
        services.AddSingleton<IAmazonDynamoDB>(client);
        services.AddTransient<IDynamoDBContext, DynamoDBContext>();
        
        return services.BuildServiceProvider();
    }
}
