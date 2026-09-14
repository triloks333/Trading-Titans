// Self-check for the blog post renderer. Run: npm run check
//
// This renderer builds HTML served from thetradingtitans.com, so anything it fails
// to escape runs on our own origin. Posts are written by admins, which is not a
// defence: a stray `</script>` in a code sample breaks out exactly as well as an
// attack would.
//
// The design being verified: everything is escaped BEFORE any markup is
// introduced, so the output cannot contain author-supplied HTML at all. That is
// stronger than sanitising afterwards, and it is why there is no sanitiser. These
// assertions are what stop someone "simplifying" that order.
//
// Same shape as web/src/lib/charges.check.ts — assert-based, no framework.

import assert from 'node:assert/strict';
import { esc, inline, renderMarkdown } from './post.js';

let checks = 0;
const ok = (label, fn) => { fn(); checks++; console.log(`  ok  ${label}`); };

console.log('blog post renderer');

ok('esc neutralises every HTML metacharacter', () => {
  assert.equal(esc('<script>'), '&lt;script&gt;');
  assert.equal(esc('a & b'), 'a &amp; b');
  assert.equal(esc('"q"'), '&quot;q&quot;');
  assert.equal(esc("it's"), 'it&#39;s');
  assert.equal(esc(null), '');
});

ok('a script tag in the body cannot survive', () => {
  const html = renderMarkdown('hello <script>alert(1)</script> world');
  assert.ok(!html.includes('<script'), 'raw script tag reached the output');
  assert.ok(html.includes('&lt;script&gt;'));
});

ok('a script tag inside a fenced code block cannot break out', () => {
  const html = renderMarkdown('```\n<script>alert(1)</script>\n```');
  assert.ok(html.startsWith('<pre><code>'));
  assert.ok(!html.includes('<script'), 'code block leaked a real script tag');
});

ok('an img src cannot be broken out of to add an event handler', () => {
  // The property that matters is not "the string onerror is absent" — as literal
  // text in a text node it is harmless, and asserting that failed for the wrong
  // reason. What must hold is that no TAG carries an event handler attribute.
  // Escaping before markup is what guarantees it: the quote is already &quot; by
  // the time the img pattern runs, so it can never close the src attribute.
  const html = inline('![x](https://a.test/i.png" onerror="alert(1))');
  assert.ok(!/<[a-z]+[^>]*\son[a-z]+\s*=/i.test(html),
    `a tag gained an event handler: ${html}`);
  assert.ok(html.includes('&quot;'), 'the quote was not escaped');
});

ok('a legitimate image still renders', () => {
  const html = inline('![alt text](https://a.test/i.png)');
  assert.ok(html.includes('<img src="https://a.test/i.png"'), html);
  assert.ok(html.includes('alt="alt text"'), html);
  assert.ok(html.includes('loading="lazy"'), html);
});

ok('only http(s) links are emitted', () => {
  for (const bad of [
    '[c](javascript:alert(1))',
    '[c](data:text/html;base64,PHNjcmlwdD4=)',
    '[c](file:///etc/passwd)',
    '[c](vbscript:msgbox)',
  ]) {
    assert.ok(!inline(bad).includes('<a '), `emitted an anchor for ${bad}`);
  }
  assert.ok(inline('[ok](https://a.test/x)').includes('<a href="https://a.test/x"'));
});

ok('links get rel=noopener', () => {
  assert.ok(inline('[x](https://a.test)').includes('rel="noopener"'));
});

ok('headings start at h2 so the title stays the only h1', () => {
  const html = renderMarkdown('# Top\n\n## Sub');
  assert.ok(html.includes('<h2>Top</h2>'), html);
  assert.ok(html.includes('<h3>Sub</h3>'), html);
  assert.ok(!html.includes('<h1'), 'body produced a second h1');
});

ok('bold, italic and inline code render', () => {
  const html = renderMarkdown('A **b** and *i* and `c` line.');
  assert.ok(html.includes('<strong>b</strong>'), html);
  assert.ok(html.includes('<em>i</em>'), html);
  assert.ok(html.includes('<code>c</code>'), html);
});

ok('lists open and close exactly once', () => {
  const html = renderMarkdown('- one\n- two\n\nafter');
  assert.equal((html.match(/<ul>/g) || []).length, 1, html);
  assert.equal((html.match(/<\/ul>/g) || []).length, 1, html);
  assert.equal((html.match(/<li>/g) || []).length, 2, html);
  assert.ok(html.includes('<p>after</p>'));
});

ok('an unterminated code fence still closes', () => {
  const html = renderMarkdown('```\nunclosed');
  assert.ok(html.trimEnd().endsWith('</code></pre>'), html);
});

ok('empty and null bodies do not throw', () => {
  assert.equal(renderMarkdown(''), '');
  assert.equal(renderMarkdown(null), '');
});

console.log(`\n${checks} checks passed`);
