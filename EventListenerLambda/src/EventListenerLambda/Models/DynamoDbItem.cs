using Amazon.DynamoDBv2.DataModel;

namespace EventListenerLambda.Models;

public class DynamoDbItem
{
    public DynamoDbItem(string itemId, string message)
    {
        ItemId = itemId;
        Message = message;
    }

    [DynamoDBHashKey(AttributeName = "PK")]
    public string ItemId { get; set; }

    public string Message { get; set; }
}