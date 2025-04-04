using Grpc.Core;
using Helloworld;

namespace GrpcService.Services;

/// <summary>
/// gRPC Greeter服务实现
/// </summary>
public class GreeterService : Greeter.GreeterBase
{
    private readonly ILogger<GreeterService> _logger;
    private const string ExpectedAuthToken = "Bearer test-token";

    /// <summary>
    /// gRPC 服务实现
    /// </summary>
    /// <param name="logger">日志记录器</param>
    public GreeterService(ILogger<GreeterService> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// 验证授权令牌
    /// </summary>
    private void ValidateAuthorization(ServerCallContext context)
    {
        var metadata = context.RequestHeaders;
        var authHeader = metadata.FirstOrDefault(h => h.Key == "authorization");

        if (authHeader == null || string.IsNullOrEmpty(authHeader.Value) || authHeader.Value != ExpectedAuthToken)
        {
            _logger.LogWarning("无效的授权令牌: {Token}", authHeader?.Value ?? "(无)");
            throw new RpcException(new Status(StatusCode.Unauthenticated, "无效的授权令牌"));
        }

        _logger.LogInformation("授权验证通过: {Token}", authHeader.Value);
    }

    public override Task<HelloReply> SayHello(HelloRequest request, ServerCallContext context)
    {
        ValidateAuthorization(context);
        
        _logger.LogInformation("收到来自 {Name} 的请求，年龄 {Age}", request.Name, request.Age);

        return Task.FromResult(new HelloReply
        {
            Message = "Hello " + request.Name,
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        });
    }

    public override async Task SayHelloServerStream(HelloRequest request,
        IServerStreamWriter<HelloReply> responseStream, ServerCallContext context)
    {
        ValidateAuthorization(context);
        
        _logger.LogInformation("开始服务端流式处理，客户端: {Name}", request.Name);

        // 发送多个响应
        for (int i = 0; i < 5; i++)
        {
            // 检查是否取消了调用
            if (context.CancellationToken.IsCancellationRequested)
                break;

            await responseStream.WriteAsync(new HelloReply
            {
                Message = $"Hello {request.Name}, 响应 #{i + 1}",
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            });

            // 等待一秒后发送下一个响应
            await Task.Delay(1000, context.CancellationToken);
        }
    }

    public override async Task<HelloReply> SayHelloClientStream(IAsyncStreamReader<HelloRequest> requestStream,
        ServerCallContext context)
    {
        ValidateAuthorization(context);
        
        _logger.LogInformation("开始客户端流式处理");

        int count = 0;
        string allNames = "";

        // 读取所有客户端消息
        await foreach (var request in requestStream.ReadAllAsync())
        {
            _logger.LogInformation("收到来自 {Name} 的流式请求", request.Name);
            allNames += (count > 0 ? ", " : "") + request.Name;
            count++;
        }

        return new HelloReply
        {
            Message = $"收到了 {count} 个请求，来自: {allNames}",
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        };
    }

    public override async Task SayHelloBidirectionalStream(IAsyncStreamReader<HelloRequest> requestStream,
        IServerStreamWriter<HelloReply> responseStream, ServerCallContext context)
    {
        ValidateAuthorization(context);
        
        _logger.LogInformation("开始双向流式处理");

        // 读取请求并立即回复
        await foreach (var request in requestStream.ReadAllAsync())
        {
            _logger.LogInformation("收到双向流中的请求: {Name}", request.Name);

            await responseStream.WriteAsync(new HelloReply
            {
                Message = $"你好 {request.Name}，收到了你的双向流请求，年龄: {request.Age}",
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            });
        }
    }
}
