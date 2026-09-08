import Foundation

/// A complete, verified Charming app, published successfully against the live
/// API before it was pasted here. Astra copies this shape.
///
/// It exists because the authoring guide alone was not enough: given ~13k
/// tokens of prose, the model wrote a plausible-looking manifest from its own
/// priors (`collections`, `fields`, `ctx` handlers), burned several attempts on
/// schema rejections, and then "succeeded" by shipping an app with no routes at
/// all. One worked example fixes what more prose did not.
enum AstraExample {
    static let module = #"""
export const manifest = {
  $schema: 'https://charm.ing/schema/app-manifest/2026-07-31.json',
  id: 'climblog',
  meta: { name: 'Climb Log', icon: { emoji: '🧗', bg: '#1f6feb' } },
  capabilities: { imports: ['charming:storage/kv@1.0'] },
};

export const routes = [
  {
    op: 'getState',
    method: 'POST',
    path: '/api/getState',
    title: 'Read all logged climbs',
    description: 'Return every logged climb, newest first.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    outputSchema: {
      type: 'object',
      required: ['climbs'],
      properties: {
        climbs: {
          type: 'array',
          items: {
            type: 'object',
            required: ['id', 'grade', 'sent', 'at'],
            properties: {
              id: { type: 'string' },
              grade: { type: 'string' },
              sent: { type: 'boolean' },
              at: { type: 'string' },
            },
            additionalProperties: false,
          },
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    public: true,
    handler: async (_input, { env }) => {
      const climbs = (await env.storage.get('climbs')) ?? [];
      return { climbs };
    },
  },
  {
    op: 'logClimb',
    method: 'POST',
    path: '/api/logClimb',
    title: 'Log a climb',
    description: 'Add a climb with its grade and whether it was sent.',
    inputSchema: {
      type: 'object',
      required: ['grade', 'sent'],
      properties: { grade: { type: 'string' }, sent: { type: 'boolean' } },
      additionalProperties: false,
    },
    outputSchema: {
      type: 'object',
      required: ['climbs'],
      properties: {
        climbs: {
          type: 'array',
          items: {
            type: 'object',
            required: ['id', 'grade', 'sent', 'at'],
            properties: {
              id: { type: 'string' },
              grade: { type: 'string' },
              sent: { type: 'boolean' },
              at: { type: 'string' },
            },
            additionalProperties: false,
          },
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    public: true,
    handler: async (input, { env }) => {
      const climbs = (await env.storage.get('climbs')) ?? [];
      climbs.unshift({
        id: crypto.randomUUID(),
        grade: input.grade,
        sent: input.sent,
        at: new Date().toISOString(),
      });
      await env.storage.put('climbs', climbs);
      return { climbs };
    },
  },
];
"""#

    static let ui = #"""
const root = document.getElementById('app');
const api = window.charming.api('climblog');
const grades = ['V0', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6'];

root.innerHTML =
  '<main class="wrap">' +
  '<h1>Climb Log</h1>' +
  '<div class="grades">' +
  grades.map((g) => '<button class="grade" data-grade="' + g + '">' + g + '</button>').join('') +
  '</div>' +
  '<label class="sent"><input type="checkbox" id="sent" checked /> sent it</label>' +
  '<ul id="list" class="list"></ul>' +
  '</main>';

const list = document.getElementById('list');

function render(climbs) {
  list.innerHTML = climbs
    .map(
      (c) =>
        '<li><span class="g">' + c.grade + '</span>' +
        '<span class="s">' + (c.sent ? 'sent' : 'attempt') + '</span>' +
        '<time>' + new Date(c.at).toLocaleDateString() + '</time></li>'
    )
    .join('');
}

for (const button of document.querySelectorAll('.grade')) {
  button.addEventListener('click', async () => {
    const { climbs } = await api.logClimb({
      grade: button.dataset.grade,
      sent: document.getElementById('sent').checked,
    });
    render(climbs);
  });
}

api.getState({}).then(({ climbs }) => render(climbs));
"""#

    static let styles = #"""
* { box-sizing: border-box; }
body { margin: 0; background: #0b0d10; color: #f2f4f7; font: 16px/1.4 -apple-system, system-ui, sans-serif; }
.wrap { min-height: 100vh; padding: 24px 20px 40px; }
h1 { font-size: 24px; margin: 0 0 20px; letter-spacing: -0.02em; }
.grades { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
.grade { padding: 18px 0; font-size: 17px; font-weight: 600; color: #f2f4f7;
  background: #171b21; border: 1px solid #262c35; border-radius: 14px; }
.grade:active { background: #1f6feb; border-color: #1f6feb; }
.sent { display: flex; align-items: center; gap: 8px; margin: 18px 0 8px; color: #9aa4b2; }
.list { list-style: none; margin: 12px 0 0; padding: 0; }
.list li { display: flex; align-items: center; gap: 12px; padding: 14px 0; border-bottom: 1px solid #1c2128; }
.g { font-weight: 700; min-width: 34px; }
.s { color: #7ee787; font-size: 14px; }
.list li time { margin-left: auto; color: #6e7781; font-size: 13px; }
"""#

    static var block: String {
        """
        ---

        WORKED EXAMPLE. This exact app published successfully. Copy its shape \
        precisely: the manifest fields, the route fields, the handler signature, \
        and the way `ui` talks to the backend. Change the domain, not the shape.

        // module
        \(module)

        // ui
        \(ui)

        // styles
        \(styles)
        """
    }
}
