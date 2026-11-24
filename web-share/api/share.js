const BACKEND = 'https://xwhjzftrzikgqweowtus.supabase.co';
const PUBLIC_KEY = 'sb_publishable_x-MshIA-X2hZ1fJJdjvtFw_dt-05xAI';
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function render(title, details, description, image, canonical) {
  const safeTitle = escapeHTML(title), safeDescription = escapeHTML(description.slice(0, 220));
  const safeImage = image ? `<meta property="og:image" content="${escapeHTML(image)}"><meta name="twitter:card" content="summary_large_image">` : '<meta name="twitter:card" content="summary">';
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${safeTitle} — LUKA</title><meta name="description" content="${safeDescription}"><meta property="og:title" content="${safeTitle}"><meta property="og:description" content="${safeDescription}"><meta property="og:type" content="website"><meta property="og:url" content="${escapeHTML(canonical)}">${safeImage}<style>body{font:17px -apple-system,BlinkMacSystemFont,sans-serif;color:#152c4c;margin:0;background:#f8fafc}main{max-width:680px;margin:6vh auto;padding:24px;background:white}h1{font-size:2rem}p{line-height:1.55;white-space:pre-wrap}.brand{font-size:1.2rem;color:#145dcb;font-weight:750}.details{font-weight:600}.photo{width:100%;height:auto;max-height:480px;object-fit:contain}</style></head><body><main><div class="brand">LUKA</div>${image ? `<img class="photo" src="${escapeHTML(image)}" alt="Photo de l’annonce">` : ''}<h1>${safeTitle}</h1><p class="details">${escapeHTML(details)}</p><p>${escapeHTML(description)}</p><p>Tout ce que tu cherches, au même endroit.</p></main></body></html>`;
}

module.exports = async function handler(req, res) {
  const kind = req.query.kind, id = req.query.id;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Cache-Control', 'no-store');
  if (!['job', 'listing'].includes(kind) || typeof id !== 'string' || !ID.test(id)) return res.status(404).send(render('Publication indisponible', '', 'Cette publication est introuvable.', null, ''));
  const table = kind === 'job' ? 'jobs' : 'listings';
  const fields = kind === 'job' ? 'title,description,company,city,contract_type' : 'title,description,city,price_xaf,status,listing_images(storage_path)';
  const query = new URLSearchParams({select:fields,id:`eq.${id}`,status:kind === 'job' ? 'eq.published' : 'in.(published,sold)',limit:'1'});
  try {
    const response = await fetch(`${BACKEND}/rest/v1/${table}?${query}`, {headers:{apikey:PUBLIC_KEY},signal:AbortSignal.timeout(8000)});
    if (!response.ok) throw new Error('backend unavailable');
    const items = await response.json();
    if (!Array.isArray(items) || !items.length) return res.status(404).send(render('Publication indisponible', '', 'Cette publication n’est plus accessible.', null, ''));
    const item = items[0];
    let image = null;
    const path = item.listing_images?.[0]?.storage_path;
    if (typeof path === 'string' && /^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg$/i.test(path)) image = `${BACKEND}/storage/v1/object/public/kutana-listing-images/${path}`;
    const details = kind === 'job' ? [item.company,item.city,item.contract_type].filter(Boolean).join(' · ') : `${new Intl.NumberFormat('fr-FR').format(item.price_xaf)} FCFA · ${item.city}${item.status === 'sold' ? ' · Vendu' : ''}`;
    const host = req.headers.host;
    const canonical = typeof host === 'string' && /^[a-z0-9.-]+$/i.test(host) ? `https://${host}/${kind === 'job' ? 'emploi' : 'annonce'}/${id}` : '';
    return res.status(200).send(render(item.title,details,item.description,image,canonical));
  } catch {
    return res.status(503).send(render('Service momentanément indisponible', '', 'Réessayez dans quelques instants.', null, ''));
  }
};
