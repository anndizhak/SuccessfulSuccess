# SuccessfulSuccess — container diagram (C4, level 2)

Updated for Lab 6 (Paste an agenda). The two new paths are numbered:
**parse** (browser → agenda parser → Bedrock) and **save** (browser → API →
Aurora). The parser never writes; the save path is the one that existed before.

```mermaid
C4Container
    title SuccessfulSuccess — containers (us-east-1)

    Person(user, "User", "Plans meetings and their agendas in a browser")

    System_Ext(cognito, "Amazon Cognito", "User pool with managed login: email + password, and Google")
    System_Ext(google, "Google", "OAuth identity provider")
    System_Ext(bedrock, "Amazon Bedrock", "Claude (Opus 5.5 via the Messages API; currently Sonnet 4.5 via Converse)")
    System_Ext(ses, "Amazon SES", "Sends the weekly report")

    Container_Boundary(aws, "AWS account, us-east-1") {
        Container(spa, "Web app", "Next.js static export on S3 + CloudFront", "Meetings, agenda form, Paste an agenda")
        Container(parser, "Agenda parser", "Lambda, function URL, outside the VPC", "Verifies the Cognito token, calls Claude, validates the agenda JSON. Never writes")
        Container_Boundary(vpc, "VPC, no NAT gateway") {
            Container(api, "Meetings API", "FastAPI on Lambda, function URL", "Meetings and agendas; stores the AI suggestion next to the saved agenda")
            ContainerDb(db, "Aurora PostgreSQL", "Serverless v2, pauses when idle", "Meetings, participants, agendas, AI suggestions")
            Container(builder, "Report builder", "Lambda", "Builds the weekly CSV")
        }
        Container(mailer, "Report mailer", "Lambda, outside the VPC", "Emails new reports")
    }

    Rel(user, spa, "Uses", "HTTPS")
    Rel(spa, cognito, "Signs in", "OIDC + PKCE")
    Rel(cognito, google, "Federates to", "OAuth 2.0")
    Rel(spa, parser, "1. parse: pasted text + access token", "HTTPS, JSON")
    Rel(parser, cognito, "Verifies tokens with", "JWKS")
    Rel(parser, bedrock, "1. parse: record_agenda tool call", "HTTPS")
    Rel(spa, api, "2. save: agenda + ai_suggestion", "HTTPS, JSON")
    Rel(api, db, "2. save: reads and writes", "PostgreSQL")
    Rel(builder, db, "Reads meetings", "PostgreSQL")
    Rel(mailer, ses, "Sends the report", "HTTPS")

    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

Not drawn, to keep the picture readable: the reports bucket, the SQS queue and
dead-letter queue, EventBridge Scheduler and the S3 gateway endpoint (Lab 5),
and the GitHub Actions deploy role (Lab 4).
