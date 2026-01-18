import * as z from "zod/v4";

const downtimeSchema = z.object({
	id: z.string(),
	details_url: z.string(),
	error: z.string(),
	started_at: z.coerce.date(),
	ended_at: z.coerce.date().or(z.null()),
	duration: z.number().or(z.null()),
});
type Downtime = z.infer<typeof downtimeSchema>;

const checkSchema = z.object({
	token: z.string(),
	url: z.string(),
	alias: z.string().or(z.null()),
	favicon_url: z.string().or(z.null()),
});
const eventCommonSchema = z.object({
	time: z.coerce.date(),
	description: z.string(),
	check: checkSchema,
});
const eventSchema = z
	.union([
		z.object({
			event: z.literal(["check.down", "check.up"]),
			downtime: downtimeSchema,
		}),
		z.object({
			event: z.literal(["check.performance_drop"]),
			apdex_dropped: z.string(),
		}),
	])
	.and(eventCommonSchema);
const eventsSchema = z.array(eventSchema);
type Event = z.infer<typeof eventSchema>;

export default {
	async fetch(request, env, _ctx): Promise<Response> {
		const uri = new URL(request.url);
		if (request.method !== "POST" && uri.pathname !== "/trigger") {
			return new Response(null, {
				status: 404,
			});
		}
		const token = uri.searchParams.get("token");
		if (!token) {
			return new Response(null, {
				status: 400,
			});
		}

		let body: unknown;
		try {
			body = await request.json();
		} catch (error) {
			console.error("received invalid json body", { error });
			return new Response(null, {
				status: 400,
			});
		}

		const parse = eventsSchema.safeParse(body);
		if (!parse.success) {
			console.warn("received unrecognized webhook", {
				body,
				error: parse.error,
			});
			return new Response(null, {
				status: 200,
			});
		}
		const events = parse.data;

		const fetches = [];
		for (const event of events) {
			let title: string = "";
			const body = event.description;
			const tags = ["updown.io", event.event];
			const alias = event.check.alias;

			switch (event.event) {
				case "check.down": {
					title = `OH NOES! ${alias ?? "SOMETHING"} IS ON FIRE!!!!`;
					tags.push("rotating_light");
					break;
				}
				case "check.up": {
					title = `${alias ? `${alias} is ` : ""}all cool now`;
					tags.push("tada");
					break;
				}
				case "check.performance_drop": {
					title = `oopsie woopsie, ${alias ? `${alias}'s` : "our"} performance is dogwater`;
					tags.push("warning");
					break;
				}
				default: {
					const _: never = event;
				}
			}

			fetches.push(
				fetch(env.NTFY_URL, {
					method: "POST",
					body,
					headers: {
						authorization: `Bearer ${token}`,
						"x-title": title,
						"x-click":
							"downtime" in event
								? event.downtime.details_url
								: `https://updown.io/${event.check.token}`,
						"x-tags": tags.join(","),
						"x-priority":
							event.event === "check.performance_drop" ? "high" : "urgent",
						"x-icon": event.check.favicon_url ?? "",
					},
				}),
			);
		}

		let failed = false;
		const results = await Promise.allSettled(fetches);
		for (const [index, result] of results.entries()) {
			const event = events[index];
			if (result.status === "rejected") {
				failed = true;
				console.error("request failed", { error: result.reason, event });
				continue;
			}

			const response = result.value;
			if (!response.ok) {
				failed = true;

				let body: string | null = null;
				try {
					body = await response.text();
				} catch {}

				console.error("request returned non-2xx status", {
					body: body,
					event,
					status: response.status,
				});
			}
		}

		if (failed) {
			return new Response(null, {
				status: 503,
			});
		}

		return new Response(null, {
			status: 200,
		});
	},
} satisfies ExportedHandler<Env>;
