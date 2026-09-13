import * as BunnySDK from "npm:@bunny.net/edgescript-sdk@0.12.1";

BunnySDK.net.http.serve(async (request: Request): Promise<Response> => {
  return new Response(JSON.stringify({
    http: {
      routers: {
        ts: {
          rule: "PathPrefix(`/`)",
          service: "ts",
          entryPoints: ["web"],
        },
      },
      services: {
        ts: {
          loadBalancer: {
            strategy: "leasttime",
            serversTransport: "ts",
            servers: [
              { "url": "https://[fd7a:115c:a1e0:7c55:ba3c:60c8:a480:41f2]:443" },
              { "url": "https://[fd7a:115c:a1e0:27d4:92b8:b4ec:86c8:76b9]:443" },
              { "url": "https://[fd7a:115c:a1e0:fb03:7e99:473a:628f:35]:443" },
            ],
            healthcheck: {
              // scheme: "http",
              // port: "8080",
              // path: "/ping",
              path: "/",
              status: 404,
              followRedirects: false,
              interval: "5s",
              timeout: "3s"
            }
          },
        },
      },
      serversTransports: {
        ts: {
          maxIdleConnsPerHost: 64,
          insecureSkipVerify: true,
          forwardingTimeouts: {
            idleConnTimeout: 0,
            readIdleTimeout: "180s"
          }
        },
      },
    }
  }), {
    status: 200,
    headers: new Headers({
      "content-type": "application/json"
    })
  });
});
