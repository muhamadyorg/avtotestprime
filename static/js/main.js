function toggleNav() {
    const navbar = document.querySelector('.navbar');
    navbar.classList.toggle('open');
}

document.addEventListener('click', function(e) {
    const navbar = document.querySelector('.navbar');
    const toggle = document.querySelector('.nav-toggle');
    if (navbar && navbar.classList.contains('open') && 
        !navbar.contains(e.target) && 
        !toggle.contains(e.target)) {
        navbar.classList.remove('open');
    }
});

function openImageModal(src) {
    const modal = document.getElementById('imageModal');
    const img = document.getElementById('modalImage');
    img.src = src;
    modal.classList.add('active');
}

function closeImageModal() {
    const modal = document.getElementById('imageModal');
    modal.classList.remove('active');
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeImageModal();
    }
});

function toggleBookmark(element, questionId) {
    fetch('/bookmark/toggle/' + questionId + '/', {
        method: 'GET',
        headers: {
            'X-Requested-With': 'XMLHttpRequest',
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.status === 'added') {
            element.classList.remove('btn-outline');
            element.classList.add('btn-warning');
            element.innerHTML = '<i class="fas fa-bookmark"></i> Saqlangan';
        } else {
            element.classList.remove('btn-warning');
            element.classList.add('btn-outline');
            element.innerHTML = '<i class="fas fa-bookmark"></i> Saqlash';
        }
    });
}
