import Cloudflare from "cloudflare";

const client = new Cloudflare();

export default {
	async fetch(request, env, _ctx): Promise<Response> {
		const uri = new URL(request.url);
		if (request.method !== "POST" && uri.pathname !== "/trigger") {
			return new Response("?", { status: 404 });
		}

		const client_ip = request.headers.get("cf-connecting-ip");
		if (!client_ip) {
			console.error("cf-connecting-ip missing");
			return new Response("idk who you are", { status: 418 });
		}
		const is_v4 = client_ip.split(".").length === 4;

		const authorization = request.headers.get("authorization");
		const token = authorization ? authorization.split(" ")[1] : null;
		if (!token) {
			return new Response("where token?", {
				status: 400,
			});
		}
		client.apiToken = token;

		await client.dns.records.edit(env.RECORD_ID, {
			zone_id: env.ZONE_ID,
			name: env.RECORD_NAME,
			type: is_v4 ? "A" : "AAAA",
			content: client_ip,
			ttl: 1,
		});

		console.info("updated record", {
			id: env.RECORD_ID,
			type: is_v4 ? "A" : "AAAA",
			name: env.RECORD_NAME,
			content: client_ip,
		});

		return new Response("kk");
	},
} satisfies ExportedHandler<Env>;
