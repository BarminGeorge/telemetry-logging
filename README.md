### 0. Prerequisites
Для выполнения блока нужен Docker.

### 1. Serilog

Ошибки важно не только показывать, но и сохранять для дальнейшего исправления.

Система логирования уже встроена в ASP.NET Core и многие компоненты благодаря этому сразу умеют писать логи.
Другой вопрос — куда сообщения от системы логирования попадут.
Тут есть простор для выбора, благо встроенная система логирования легко расширяется.

Расширить можно с помощью библиотеки Serilog.
Serilog может генерировать сообщения в обычном формате человекочитаемых строчек,
но также поддерживает так называемое «структурное логирование», т.е. может генерировать сообщения в виде JSON.
Сообщения в виде JSON легче обрабатывать автоматически, а еще можно сразу отправлять в сервис централизованного
сбора и хранения логов.
Писать Serilog умеет и в консоль, и в файлы, и в удаленные сервисы сбора логов,
а еще можно написать своего «потребителя логов», в который Serilog будет писать.

**Дополнительные пояснения про структурное логирование**

Структурное логирование и централизованное хранение логов в специальном сервисе — это современный тренд.
Это позволяет разработчикам в одном месте искать логи последних событий при разборе обращений от пользователей,
либо других проблем в сервисе. Но для того, чтобы работал поиск, надо ключевые значения из сообщения логов вычленить.
Чтобы сервису сбора логов не приходилось этого делать, лучше сразу логировать сообщения в виде JSON,
в полях которого записывать необходимые ключевые значения.


Пришло время добавить логирование.

1. Подключи NuGet-пакеты Serilog и Serilog.AspNetCore. Можно ещё Serilog.Enrichers.Environment, чтобы обогащать
логи информацией из окружения.

2. Подключи Serilog к хосту, чтобы использовался он, а не реализация логирования от Microsoft.
```cs
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateLogger();

...

builder.Host.UseSerilog();

builder.Services.AddSerilog((hostingContext, loggerConfiguration) =>
            loggerConfiguration.ReadFrom.Configuration(hostingContext.Configuration));
```
Serilog можно конфигурировать через код, но здесь для конфигурации используется `IConfiguration` хоста,
которая собирается стандартным образом.

3. Положи настройки логирования в файл `appsettings.json`, раз уж настроил, что они берутся из `IConfiguration`.
   Настройки обычного логирования от Microsoft при этом можно удалить. В итоге должно быть так:
```json
{
  "Serilog": {
    "WriteTo": [
      {
        "Name": "File",
        "Args": {
          "path": ".logs/log-.txt",
          "formatter": "Serilog.Formatting.Compact.RenderedCompactJsonFormatter, Serilog.Formatting.Compact",
          "rollingInterval": "Day",
          "rollOnFileSizeLimit": true
        }
      },
      {
        "Name": "Console",
        "Args": {
          "outputTemplate": "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties:j}{NewLine}{Exception}"
        }
      }
    ],
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "System": "Warning"
      }
    }
  },
  "AllowedHosts": "*"
}
```

4. Обрати внимание на конфигурацию. В ней настроен `rollingInterval` и `rollOnFileSizeLimit`.
   В реальных приложениях за день могут накопиться сотни мегабайт логов, если не больше.
   Крупными файлами неудобно манипулировать, поэтому лучше логи разбивать по датам, а еще по размеру,
   если почему-то логов за сутки слишком много. Добавление этих настроек обеспечивает разделение на файлы.

5. Перейди по какой-нибудь ссылке.
   Убедись, что оно было залогировано в файле `/.logs/log-{current-date}` в виде JSON.

*Замечание. На момент 2021.02.12 использование UseSerilog ломает логику автоматического запуска браузера в VS Code*
*и, возможно, в других IDE, потому что эта логика ориентируется на формат сообщений из логов:*
*[Подробнее в этом и связанных issue](https://github.com/serilog/serilog/issues/1408).*


Кроме ошибок полезно логировать вообще все запросы. Как минимум, это помогает понять последовательность
действий пользователя, которые к ошибке привели. С Serilog это элементарно — достаточно добавить промежуточный слой!

Добавь строчку `app.UseSerilogRequestLogging();` сразу после промежуточного слоя статических файлов,
т.к. информация об обращении к статике не особо интересна.

Сделай несколько запросов и убедись, что они залогировались в виде JSON в файлах,
а также в читабельном виде (а не в виде JSON) попали в отладочную консоль.
В консоли сообщения должны выглядеть примерно так:
`[14:12:26 INF] HTTP GET / responded 200 in 58.2818 ms {"SourceContext": "Serilog.AspNetCore.RequestLoggingMiddleware"}`


Еще одна нередкая ситуация — это когда конфигурация приложения оказалась некорректной по той или иной причине.
Чтобы просимулировать эту ситуацию, полностью удали содержимое файла `appsettings.Development.json`, ведь там осталась только
ненужная конфигурация логирования от Microsoft, которую не жалко. А вот сам файл оставь.

Теперь попробуй запустить приложение.

Вообще-то оно должно сразу упасть. А что же в логах? Ничего?
Относительно редкая ситуация, когда приложение даже не может стартануть,
но все равно было бы неплохо зафиксировать что-то в логах.
А значит логирование надо сконфигурировать хотя бы минимальным образом еще до чтения конфигурации.

Оберни конфигурациию, создание и запуск приложения в try-catch и воспользуйся объектов `Log` для логирования. Добавь к нему
логирование в файл:
```csharp
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File("logs/start-host-log-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();
```
Теперь будет залогировано любое необработанное исключение, из-за которого упадет весь хост.
Но важно, что здесь до построения хоста добавляется логирование в `.logs/start-host-log-{current-date}.txt`.
Благодаря этому, если до обычного конфигурирования логирования произойдет исключение,
оно будет залогировано в `start-host-log`. При этом после успешной конфигурации логирования по `IConfiguration`,
`Logger` будет заменен на сконфигурированный по `IConfiguration`.

Снова попробуй запустить приложение. После падения убедись, что появился файл `.logs/start-host-log-{current-date}.txt`,
в котором залогировано исключение.

Все же придется написать в `appsettings.Development.json` пустой объект `{}`, чтобы приложение перестало падать.


### 2. ELK stack
ELK = Elasticsearch (СУБД + движок) + Logstash (средство для сборка логов) + Kibana (средство визуализации).
Это самый популярный стек для централизованного сборка логов.

В репозитории уже есть всё для разворачивания ELK-стека локально с помощью docker compose.
Выполни команды:
```sh
docker compose up setup
```
```sh
docker compose up
```

Чтобы проверить, что всё ок, зайди по адресу http://localhost:5601 и введи следующие данные:
Login: elastic
Password: changeme

Проверь, что открывается интерфейс Kibana.

### 3. Serilog + ELK
Теперь настроим отправку логов из нашего приложения в ELK.

Установи пакет Elastic.Serilog.Sinks.

Добавь к настройке лога внутри `AddSerilog` примерн следующий код:
```csharp
builder.Services.AddSerilog((_, lc) => lc.Enrich.FromLogContext()
    .WriteTo.Elasticsearch([new Uri("http://localhost:9200")], opts =>
    {
        opts.DataStream = new DataStreamName("logs", "telemetry-loggin", "demo");
        opts.BootstrapMethod = BootstrapMethod.Failure;
        opts.ConfigureChannel = channelOpts =>
        {
            channelOpts.BufferOptions = new BufferOptions
            {
                ExportMaxConcurrency = 10
            };
        };
    }, transport =>
    {
        transport.Authentication(new BasicAuthentication("elastic", "changeme")); // Basic Auth
        // transport.Authentication(new ApiKey(base64EncodedApiKey)); // ApiKey
        transport.OnRequestCompleted(d => Console.WriteLine($"es-req: {d.DebugInformation}"));
    })
    .Enrich.WithProperty("Environment", builder.Environment.EnvironmentName)
    .ReadFrom.Configuration(builder.Configuration));

```
Подробнее про конфигурацию "трубы" до ELK можно прочитать [здесь](https://www.elastic.co/guide/en/ecs-logging/dotnet/current/serilog-data-shipper.html).

Замени `builder.Services.AddSerilog(...)` на
```csharp
builder.Services.AddSerilog(Log.Logger);
```

Теперь запусти приложение, потыкай по ссылкам. Проверь, что логирование в консоль не сломалось!
Открой Kibana, нажми на "бургер-меню" (три полоски слева) -> Analytics -> Discover. Проверь, что там есть твои логи.

### 4. Логирование в приложении
Чтобы залогировать что-нибудь в приложении, достаточно добавить MS-ный `ILogger<T>` в нужный класс.
Для примера добавь в `Index.cshtml.cs` следующий код (логгер там уже подключен):

```csharp
public void OnGet()
{
    var myName = "..."; // ваше имя
   _logger.LogInformation("Sample log. My name is {MyName}", myName);
}
```

Запусти приложение, открой главную, после чего убедись с помощью поиска в Kibana, что твой лог записался.
Проверь, что среди свойств записи есть поле MyName со значением, которое было задано в переменной `myName`.
Так добавляются новые свойства в логи.

### 4. OpenTelemetry
Теперь посмотрим на то, как отправлять логи централизованно в трубу в OpenTelemetry.
Подключи пакеты
```
dotnet add package OpenTelemetry.Exporter.Console
dotnet add package OpenTelemetry.Extensions.Hosting
```

Добавь в Program.cs код
```cs
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService("<ВАШЕ_НАЗВАНИЕ_ПРИЛОЖЕНИЯ>"))
    .WithLogging()
    .UseOtlpExporter();
```

Переменные окружения возьми с предыдущего занятия, ServiceName тоже задай свой.

Отключи Serilog, запусти приложение, открой https://fiit-backend-telemetry.duckdns.org, создай новый дашборд, в качестве источника выбери Loki и посмотри логи.