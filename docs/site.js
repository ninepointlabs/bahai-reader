const toggle = document.querySelector('#palette');
try { document.body.classList.toggle('light', localStorage.getItem('reader-site-theme') === 'light'); } catch {}
function label() { toggle.setAttribute('aria-label', document.body.classList.contains('light') ? 'Switch to dark theme' : 'Switch to light theme'); }
label();
toggle.addEventListener('click', () => {
  document.body.classList.toggle('light');
  try { localStorage.setItem('reader-site-theme', document.body.classList.contains('light') ? 'light' : 'dark'); } catch {}
  label();
});
