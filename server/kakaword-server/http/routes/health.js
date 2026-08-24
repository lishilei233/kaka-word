export function registerHealthRoute(app, provider) {
    app.get("/health", (c) => c.json({ ok: true, provider }));
}
