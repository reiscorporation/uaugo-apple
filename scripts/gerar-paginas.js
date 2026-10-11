// Gera o site público (pasta public/, Firebase Hosting) a partir dos MESMOS
// textos que o app mostra (assets/legal/*.md): Termos, Política de Privacidade
// e a página "Como excluir seus dados" exigida pela Google Play.
//
// Rodar na raiz do projeto:   node scripts/gerar-paginas.js
// Publicar:                   firebase deploy --only hosting --project helpaitechcomboio
// Endereços: https://helpaitechcomboio.web.app/privacidade (e /termos, /excluir-dados)

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const out = path.join(root, "public");
fs.mkdirSync(out, { recursive: true });

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const inline = (s) => esc(s)
  .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
  .replace(/([\w.+-]+@[\w-]+\.[\w.]+)/g, '<a href="mailto:$1">$1</a>');

/** Markdown simples (títulos, listas, parágrafos, negrito) para HTML. */
function md(text) {
  const html = [];
  let list = false;
  const close = () => { if (list) { html.push("</ul>"); list = false; } };
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trimEnd();
    if (!line.trim()) { close(); continue; }
    const h = line.match(/^(#{1,3})\s+(.*)$/);
    if (h) { close(); html.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`); continue; }
    const li = line.match(/^\s*[-*]\s+(.*)$/);
    if (li) { if (!list) { html.push("<ul>"); list = true; } html.push(`<li>${inline(li[1])}</li>`); continue; }
    close();
    html.push(`<p>${inline(line)}</p>`);
  }
  close();
  return html.join("\n");
}

const page = (title, body) => `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>
  :root { --bg:#fff; --fg:#0f1b2d; --muted:#4a5d75; --accent:#d9560b; --line:#dbe3ee; }
  @media (prefers-color-scheme: dark) { :root { --bg:#0f1b2d; --fg:#eaf1fa; --muted:#a9bbd1; --accent:#ff7a1a; --line:#26405f; } }
  body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.6 system-ui,-apple-system,Segoe UI,Roboto,sans-serif; }
  main { max-width:760px; margin:0 auto; padding:24px 16px 64px; }
  h1 { font-size:1.6rem; line-height:1.3; } h2 { font-size:1.2rem; margin-top:2rem; }
  a { color:var(--accent); } nav { border-bottom:1px solid var(--line); padding:12px 16px; text-align:center; }
  nav a { margin:0 10px; text-decoration:none; font-weight:600; }
  footer { color:var(--muted); font-size:.9rem; margin-top:3rem; border-top:1px solid var(--line); padding-top:12px; }
</style>
</head>
<body>
<nav><a href="/termos">Termos de Uso</a><a href="/privacidade">Privacidade</a><a href="/excluir-dados">Excluir dados</a></nav>
<main>
${body}
<footer>UauGo — Ricardo Reis / HelpAITech · <a href="mailto:helpaitech.ricardo@gmail.com">helpaitech.ricardo@gmail.com</a></footer>
</main>
</body>
</html>
`;

const read = (f) => fs.readFileSync(path.join(root, "assets", "legal", f), "utf8");
const termos = read("termos_de_uso.md");
const privacidade = read("politica_de_privacidade.md");

fs.writeFileSync(path.join(out, "termos.html"), page("Termos de Uso — UauGo", md(termos)));
fs.writeFileSync(path.join(out, "privacidade.html"), page("Política de Privacidade — UauGo", md(privacidade)));

// "Como excluir seus dados": seção 9 da Política + o que é apagado.
const secao9 = (privacidade.split(/^## 9\. .*$/m)[1] || "").split(/^## /m)[0].trim();
fs.writeFileSync(path.join(out, "excluir-dados.html"), page("Excluir seus dados — UauGo", md(
  `# Como excluir sua conta e seus dados do UauGo\n\n${secao9}\n\n` +
  "## O que é apagado\n\n" +
  "- Conta (login), autorizações e registro do aceite dos Termos.\n" +
  "- Participação em expedições (nome, veículo, foto e posições) e pedidos de SOS.\n" +
  "- Cadastro no clube e avisos enviados.\n" +
  "- Dados guardados no celular (histórico de viagens, configurações).\n\n" +
  "## O que pode ficar\n\n" +
  "- Alertas da comunidade que você reportou ficam até vencer (de 1 hora a 7 dias), **sem identificar você**.\n\n" +
  "Pedidos por e-mail são atendidos em até **15 dias**.")));

fs.writeFileSync(path.join(out, "index.html"), page("UauGo", md(
  "# UauGo\n\nNavegação e viagens em grupo de moto e de carro.\n\n" +
  "- **Termos de Uso:** /termos\n- **Política de Privacidade:** /privacidade\n- **Excluir seus dados:** /excluir-dados"))
  .replace(/(\/(termos|privacidade|excluir-dados))<\/li>/g, '<a href="$1">$1</a></li>'));

console.log("Páginas geradas em public/: index, termos, privacidade, excluir-dados");
