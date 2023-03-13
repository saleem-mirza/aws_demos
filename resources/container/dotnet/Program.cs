internal class Program
{
    private static async Task Main(string[] args)
    {
        var s3Bucket = Environment.GetEnvironmentVariable("s3_bucket");
        var s3ObjectKey = Environment.GetEnvironmentVariable("s3_object_key");

        if (s3Bucket is null || s3ObjectKey is null)
        {
            Console.Error.WriteLine("Missing required environment varialbles");
            Environment.Exit(-1);
        }

        var s3Client = new Amazon.S3.AmazonS3Client();
        try
        {
            var eventTime = Environment.GetEnvironmentVariable("event_time");
            await s3Client.CopyObjectAsync(
                s3Bucket,
                s3ObjectKey,
                s3Bucket,
                $"processed/{eventTime}_{s3ObjectKey.Split("/").Last()}"
            );
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            Environment.Exit(-1);
        }
    }
}