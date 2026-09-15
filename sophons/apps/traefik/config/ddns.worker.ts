/// <reference types="deno" />

const POLL_INTERVAL_MS = Deno.env.get("POLL_INTERVAL_MS") || "60000";
const POLL_INTERVAL = parseFloat(POLL_INTERVAL_MS);
const UNIFI_CA_CRT = Deno.env.get("UNIFI_CA_CRT") || panic("UNIFI_CA_CRT where???");
const UNIFI_BASE_URL = Deno.env.get("UNIFI_BASE_URL") || panic("UNIFI_BASE_URL where???");
const UNIFI_USERNAME = Deno.env.get("UNIFI_USERNAME") || panic("UNIFI_USERNAME where???");
const UNIFI_PASSWORD = Deno.env.get("UNIFI_PASSWORD") || panic("UNIFI_PASSWORD where???");
const UNIFI_GATEWAY = Deno.env.get("UNIFI_GATEWAY") || panic("UNIFI_GATEWAY where???");
const ISP_NAME = Deno.env.get("ISP_NAME") || panic("ISP_NAME where???")
const WANS = ["WAN", "WAN2"];
const WANS_KEYS = ["wan1", "wan2"];

const DNS_ZONE_ID = Deno.env.get("DNS_ZONE_ID") || panic("DNS_ZONE_ID where???");
const DNS_RECORD_IDS = (Deno.env.get("DNS_RECORD_IDS") || panic("DNS_RECORD_IDS where???")).split(",");
const BUNNY_API_KEY = Deno.env.get("BUNNY_API_KEY") || panic("BUNNY_API_KEY where???");

function panic(message: string): never {
  throw new Error(message);
}

async function* every(ms: number) {
  yield;
  while (true) {
    await new Promise<void>(resolve => {
      setTimeout(resolve, ms)
    });
    yield;
  }
}

async function login() {
  const loginResponse = await fetch(`${UNIFI_BASE_URL}/api/auth/login`, {
    client: unifiClient,
    method: "POST",
    headers: new Headers({ "content-type": "application/json" }),
    body: JSON.stringify({
      username: UNIFI_USERNAME,
      password: UNIFI_PASSWORD,
    }),
  });

  if (!loginResponse.ok) {
    console.error("ERROR: unifi login request failed: " + await loginResponse.text())
    return;
  }

  const setCookies = loginResponse.headers.getSetCookie();

  cookie = setCookies
    .map((value) => value.split(";", 1)[0])
    .join("; ");
}

let cookie = "";
let lastAppliedState: { wanIP: string; } = { wanIP: "" };
const unifiClient = Deno.createHttpClient({ caCerts: [UNIFI_CA_CRT] });

for await (const _ of every(POLL_INTERVAL)) {
  if (!cookie) {
    await login();
  }

  const deviceRes = await
    fetch(`${UNIFI_BASE_URL}/proxy/network/api/s/default/stat/device`, {
      client: unifiClient,
      headers: new Headers({
        "cookie": cookie
      }),
    });


  if (!deviceRes.ok) {
    if (deviceRes.status === 401) {
      cookie = "";
    }
    console.error("ERROR: unifi request failed: " + await deviceRes.text());
    continue;
  }


  const gwDevice = (await deviceRes.json()).data.find(d => d.name === UNIFI_GATEWAY);
  const wanIndex = WANS.findIndex(WAN => gwDevice.active_geo_info[WAN].isp_name === ISP_NAME)
  const wanIP = gwDevice[WANS_KEYS[wanIndex]].ipv6.find(ip => !ip.startsWith("fe80:"))

  if (
    lastAppliedState.wanIP === wanIP
  ) {
    continue;
  }

  console.debug(`update records: ${DNS_RECORD_IDS.join(",")} to: ${wanIP}`);
  let anyErrorOccurred = false;
  await Promise.allSettled(DNS_RECORD_IDS.map(id => fetch(`https://api.bunny.net/dnszone/${DNS_ZONE_ID}/records/${id}`, {
    method: "POST",
    headers: new Headers({
      "content-type": "application/json",
      "accesskey": BUNNY_API_KEY,
    }),
    body: JSON.stringify({ Value: wanIP })
  }).then(async response => {
    if (!response.ok) {
      anyErrorOccurred = true;
      console.error("ERROR: bunny request failed: " + await response.text());
    }
  })));

  if (!anyErrorOccurred) {
    lastAppliedState.wanIP = wanIP;
  }
}


export { }
