// HA KioskOS — Kiosk Builder UI

// Auto-refresh dashboardu každých 30 sekund (aktualizuje online status)
if (document.querySelector('.kiosk-grid') || document.querySelector('.empty-state')) {
    setInterval(function() {
        location.reload();
    }, 30000);
}

// Potvrzení smazání (záložní pro případ že onsubmit nefunguje)
document.querySelectorAll('form[action*="delete"]').forEach(function(form) {
    form.addEventListener('submit', function(e) {
        const hostname = form.action.split('/')[form.action.split('/').length - 2];
        if (!confirm('Opravdu smazat kiosk ' + hostname + '?')) {
            e.preventDefault();
        }
    });
});
