using Amazon.DynamoDBv2.DataModel;

namespace EventListenerLambda.Models;

public class DynamoDbItem
{
    [DynamoDBHashKey(AttributeName = "ItemId")]
    public string ItemId { get; set; }

    public string Message { get; set; }
}