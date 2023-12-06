using Newtonsoft.Json;

namespace EventListenerLambda.Models;

public class SNSEnvelope
{
    [JsonProperty("Message")]
    public string Message { get; set; }
}