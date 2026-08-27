// WebMCP tool layer: exposes the preview UI to a browser AI agent.
//
// Every tool wraps something the page already does, so the agent drives
// trmnlp the same way a person does. Registration is best-effort — browsers
// without document.modelContext just get the normal UI.

const webmcp = {};

// Chrome's tool-security guidance suggests ~1.5K per tool output. It is not
// enforced, but agents reason badly over long dumps, so we summarize instead
// of truncating wherever a summary is more useful than a prefix.
webmcp.MAX_OUTPUT_CHARACTERS = 1500;

webmcp.text = function (value, budget) {
  const body = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  const limit = budget || webmcp.MAX_OUTPUT_CHARACTERS;
  const clipped = body.length > limit
    ? body.slice(0, limit) + `\n… truncated, ${body.length - limit} more characters`
    : body;
  return { content: [{ type: "text", text: clipped }] };
};

webmcp.VIEWS = ["full", "half_horizontal", "half_vertical", "quadrant", "shared"];

webmcp.viewSchema = {
  type: "string",
  enum: webmcp.VIEWS,
  description: "Which screen layout to act on. 'shared' is the partial included by all four."
};

// Flatten the merge-variable tree into `path = preview` lines. An agent
// debugging a blank field needs the available paths far more than it needs
// the full payload, and the paths fit in the output budget where the
// payload would not.
webmcp.summarizeData = function (value, prefix = "", lines = [], limit = 60) {
  if (lines.length >= limit) return lines;

  if (Array.isArray(value)) {
    lines.push(`${prefix} = array of ${value.length}`);
    if (value.length > 0) webmcp.summarizeData(value[0], `${prefix}[0]`, lines, limit);
  } else if (value && typeof value === "object") {
    for (const key of Object.keys(value)) {
      webmcp.summarizeData(value[key], prefix ? `${prefix}.${key}` : key, lines, limit);
      if (lines.length >= limit) break;
    }
  } else {
    const preview = String(value);
    lines.push(`${prefix} = ${preview.length > 60 ? preview.slice(0, 60) + "…" : preview}`);
  }
  return lines;
};

webmcp.currentView = () => document.querySelector("meta[name='trmnl-view']").content;

webmcp.register = async function () {
  const modelContext = document.modelContext;
  if (!modelContext) {
    console.info("WebMCP unavailable — start Chrome with --enable-blink-features=WebMCP");
    return;
  }

  const tool = (definition) => modelContext.registerTool(definition);
  const readOnly = { readOnlyHint: true };
  // Merge variables and rendered output both carry data the plugin fetched
  // from a third party, so they are untrusted input to the agent.
  const readOnlyUntrusted = { readOnlyHint: true, untrustedContentHint: true };

  await tool({
    name: "list_screen_views",
    description: "Lists the screen layouts this plugin can be previewed in.",
    annotations: readOnly,
    execute: () => webmcp.text(webmcp.VIEWS.join(", "))
  });

  await tool({
    name: "get_markup",
    description: "Returns the Liquid template source for one screen layout.",
    inputSchema: { type: "object", properties: { view: webmcp.viewSchema } },
    annotations: readOnly,
    execute: async ({ view }) => {
      const response = await fetch(`/api/markup?view=${encodeURIComponent(view || webmcp.currentView())}`);
      const body = await response.json();
      return webmcp.text(body.error || body.markup || "(empty template)");
    }
  });

  await tool({
    name: "get_markup_guide",
    description:
      "The TRMNL template guide: layout, typography, components, utility classes, charts, Liquid " +
      "syntax and worked examples. Call it with no section to list the sections, then ask for one " +
      "by title. Read the sections you need before writing markup, because TRMNL templates use a " +
      "specific class vocabulary that ordinary HTML and CSS will not match.",
    inputSchema: {
      type: "object",
      properties: {
        section: {
          type: "string",
          description: "A section title from the listing. Omit it to list every section."
        }
      }
    },
    annotations: readOnly,
    execute: async ({ section }) => {
      const query = section ? `?section=${encodeURIComponent(section)}` : "";
      const response = await fetch(`/api/markup_guide${query}`);
      const body = await response.json();

      if (!response.ok) return webmcp.text(body.error);
      if (!body.available) {
        return webmcp.text(
          "The template guide was not fetched into this instance. It lives at " +
          "github.com/usetrmnl/trmnl-agent-skills."
        );
      }
      if (body.sections) {
        return webmcp.text(
          body.sections.map((s) => `${"  ".repeat(s.level - 2)}${s.title}`).join("\n"), 4000
        );
      }
      return webmcp.text(`## ${body.title}\n\n${body.body}`, 8000);
    }
  });

  await tool({
    name: "set_markup",
    description:
      "Replaces the Liquid template source for one screen layout and reloads the preview. " +
      "Overwrites the file, so read it with get_markup first, and consult get_markup_guide "
      + "so the markup uses TRMNL's own classes rather than generic HTML.",
    inputSchema: {
      type: "object",
      properties: {
        view: webmcp.viewSchema,
        markup: { type: "string", description: "The complete new Liquid template source." }
      },
      required: ["view", "markup"]
    },
    execute: async ({ view, markup }) => {
      const response = await fetch("/api/markup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ view, markup })
      });
      const body = await response.json();
      if (!response.ok) return webmcp.text(`Failed: ${body.error}`);
      trmnlp.fetchPreview();
      return webmcp.text(`Wrote ${body.bytes} bytes to ${body.view}.liquid; preview reloaded.`);
    }
  });

  await tool({
    name: "reset_markup",
    description:
      "Restores every template this session overwrote to the content it had when the server " +
      "started. Use it to undo a set_markup you regret, or to clean up a shared demo.",
    execute: async () => {
      const body = await (await fetch("/api/markup/reset", { method: "POST" })).json();
      trmnlp.fetchPreview();
      return webmcp.text(
        body.restored.length ? `Restored: ${body.restored.join(", ")}.` : "Nothing had been changed."
      );
    }
  });

  await tool({
    name: "get_merge_variables",
    description:
      "Lists the merge-variable paths available to the Liquid template, with a preview of each " +
      "value. Use this to check what a template can reference before editing it.",
    annotations: readOnlyUntrusted,
    execute: async () => {
      const state = trmnlp.picker?.state;
      const query = state ? `?width=${state.width}&height=${state.height}` : "";
      const data = await (await fetch(`/data${query}`)).json();
      return webmcp.text(webmcp.summarizeData(data).join("\n"));
    }
  });

  await tool({
    name: "get_rendered_html",
    description:
      "Returns the rendered HTML body for a screen layout, after Liquid has run. Use this to see " +
      "what the template actually produced when the preview looks wrong.",
    inputSchema: { type: "object", properties: { view: webmcp.viewSchema } },
    annotations: readOnlyUntrusted,
    execute: async ({ view }) => {
      const html = await (await fetch(`/render/${view || webmcp.currentView()}.html`)).text();
      const body = html.match(/<body[^>]*>([\s\S]*)<\/body>/i);
      return webmcp.text((body ? body[1] : html).replace(/\s+/g, " ").trim());
    }
  });

  await tool({
    name: "refresh_data",
    description: "Re-fetches the plugin's data from its source and reloads the preview.",
    execute: async () => {
      await fetch("/poll");
      trmnlp.fetchPreview();
      return webmcp.text("Re-polled the plugin's data source; preview reloaded.");
    }
  });

  await tool({
    name: "set_device_model",
    description: "Switches the preview to a different TRMNL device model.",
    inputSchema: {
      type: "object",
      properties: { model: { type: "string", description: "Device model name from the picker." } },
      required: ["model"]
    },
    execute: ({ model }) => {
      const select = document.querySelector("[data-model-select]");
      const match = [...select.options].find((option) => option.value === model);
      if (!match) {
        return webmcp.text(`Unknown model. Available: ${[...select.options].map((o) => o.value).join(", ")}`);
      }
      select.value = model;
      select.dispatchEvent(new Event("change", { bubbles: true }));
      return webmcp.text(`Preview switched to ${model}.`);
    }
  });

  for (const [name, selector, what] of [
    ["toggle_orientation", "[data-orientation-toggle]", "orientation"],
    ["toggle_dark_mode", "[data-dark-mode-toggle]", "dark mode"]
  ]) {
    await tool({
      name,
      description: `Toggles the preview's ${what}.`,
      execute: () => {
        document.querySelector(selector).click();
        return webmcp.text(`Toggled ${what}.`);
      }
    });
  }

  console.info(`WebMCP: registered ${(await modelContext.getTools()).length} tools`);
};

document.addEventListener("DOMContentLoaded", () => {
  webmcp.register().catch((error) => console.warn("WebMCP registration failed:", error));
});
