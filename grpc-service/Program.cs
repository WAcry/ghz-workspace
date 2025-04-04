using GrpcService.Services;

var builder = WebApplication.CreateBuilder(args);

// 添加服务到容器
builder.Services.AddGrpc();

// 添加gRPC反射服务
builder.Services.AddGrpcReflection();

// 配置Kestrel
builder.WebHost.ConfigureKestrel(options =>
{
    // 设置HTTP/2无TLS的端口
    options.ListenAnyIP(50051, listenOptions =>
    {
        listenOptions.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http2;
    });
});

// 添加CORS支持
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", builder =>
    {
        builder.AllowAnyOrigin()
               .AllowAnyMethod()
               .AllowAnyHeader()
               .WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding", "Grpc-Accept-Encoding");
    });
});

var app = builder.Build();

// 配置中间件管道
app.UseRouting();
app.UseCors("AllowAll");

// 配置gRPC服务
app.MapGrpcService<GreeterService>();

// 映射gRPC反射服务
app.MapGrpcReflectionService();

app.MapGet("/", () => "gRPC服务正在监听端口: 50051");

// 输出服务启动信息
app.Lifetime.ApplicationStarted.Register(() =>
{
    Console.WriteLine($"gRPC服务已启动！正在监听端口: 50051");
});

app.Run();
