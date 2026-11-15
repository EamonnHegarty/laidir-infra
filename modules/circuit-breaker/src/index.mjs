// Cost circuit breaker: when the request-flood alarm enters ALARM, set the
// throttle of every route on the stage to 0, so API Gateway answers 429 and
// no Lambda, DynamoDB or log costs accrue. A human resets it via Terraform.
import {
  ApiGatewayV2Client,
  GetStageCommand,
  UpdateStageCommand,
} from "@aws-sdk/client-apigatewayv2";

const client = new ApiGatewayV2Client({});
const { API_ID, STAGE_NAME } = process.env;
const OFF = { ThrottlingBurstLimit: 0, ThrottlingRateLimit: 0 };

const parse = (record) => {
  try {
    return JSON.parse(record.Sns.Message);
  } catch {
    return {};
  }
};

export const handler = async (event) => {
  const alarms = (event.Records ?? []).map(parse);
  if (!alarms.some((a) => a.NewStateValue === "ALARM")) {
    console.log(JSON.stringify({ msg: "ignored", states: alarms.map((a) => a.NewStateValue) }));
    return { tripped: false };
  }

  const stage = await client.send(new GetStageCommand({ ApiId: API_ID, StageName: STAGE_NAME }));

  // Routes with their own settings must be zeroed individually; the rest inherit the default.
  const routeSettings = Object.fromEntries(
    Object.entries(stage.RouteSettings ?? {}).map(([routeKey, settings]) => [routeKey, { ...settings, ...OFF }]),
  );

  await client.send(
    new UpdateStageCommand({
      ApiId: API_ID,
      StageName: STAGE_NAME,
      DefaultRouteSettings: { ...stage.DefaultRouteSettings, ...OFF },
      RouteSettings: routeSettings,
    }),
  );

  console.log(
    JSON.stringify({
      msg: "circuit breaker tripped: all throttles set to 0",
      apiId: API_ID,
      stage: STAGE_NAME,
      routes: Object.keys(routeSettings),
      alarm: alarms.find((a) => a.NewStateValue === "ALARM")?.AlarmName,
    }),
  );
  return { tripped: true };
};
