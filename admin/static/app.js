// Refresh the status box every 4 seconds (no personal data, only the numbers shown on the page)
setInterval(async () => {
  try {
    const r = await fetch('/api/status', {credentials: 'same-origin'});
    if (!r.ok) return;
    const d = await r.json();
    const box = document.getElementById('status');
    if (!box) return;
    const up = box.querySelector('b');
    up.textContent = d.online ? 'ONLINE' : 'OFFLINE';
    up.className = d.online ? 'up' : 'down';
    box.querySelectorAll('p')[2].querySelector('b').textContent = d.players.length;
  } catch (e) {}
}, 4000);
