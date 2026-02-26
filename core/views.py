import json
import random
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import login_required, user_passes_test
from django.contrib.auth.models import User
from django.http import JsonResponse
from django.db.models import Q, Avg, Count
from .models import Question, Bookmark, TestSession, TestAnswer


def is_admin(user):
    return user.is_staff


def index(request):
    if request.user.is_authenticated:
        if request.user.is_staff:
            return redirect('admin_dashboard')
        return redirect('dashboard')
    return redirect('login')


def login_view(request):
    if request.user.is_authenticated:
        return redirect('index')
    error = None
    if request.method == 'POST':
        username = request.POST.get('username', '')
        password = request.POST.get('password', '')
        user = authenticate(request, username=username, password=password)
        if user is not None:
            login(request, user)
            if user.is_staff:
                return redirect('admin_dashboard')
            return redirect('dashboard')
        else:
            error = "Login yoki parol xato!"
    return render(request, 'login.html', {'error': error})


def logout_view(request):
    logout(request)
    return redirect('login')


@login_required
def dashboard(request):
    total_questions = Question.objects.count()
    bookmark_count = Bookmark.objects.filter(user=request.user).count()
    test_count = TestSession.objects.filter(user=request.user, completed=True).count()
    sessions = TestSession.objects.filter(user=request.user, completed=True)
    avg_score = 0
    if sessions.exists():
        total = sum(s.score_percent for s in sessions)
        avg_score = round(total / sessions.count())
    return render(request, 'dashboard.html', {
        'total_questions': total_questions,
        'bookmark_count': bookmark_count,
        'test_count': test_count,
        'avg_score': avg_score,
    })


@login_required
def all_questions(request):
    questions = Question.objects.all()
    user_bookmarks = set(Bookmark.objects.filter(user=request.user).values_list('question_id', flat=True))
    return render(request, 'all_questions.html', {
        'questions': questions,
        'user_bookmarks': user_bookmarks,
    })


@login_required
def question_detail(request, question_id):
    question = get_object_or_404(Question, id=question_id)
    is_bookmarked = Bookmark.objects.filter(user=request.user, question=question).exists()
    return render(request, 'question_detail.html', {
        'question': question,
        'is_bookmarked': is_bookmarked,
    })


@login_required
def search_questions(request):
    query = request.GET.get('q', '')
    questions = Question.objects.all()
    if query:
        questions = questions.filter(
            Q(text__icontains=query) |
            Q(variant_a__icontains=query) |
            Q(variant_b__icontains=query) |
            Q(variant_c__icontains=query) |
            Q(variant_d__icontains=query) |
            Q(number__icontains=query)
        )
    user_bookmarks = set(Bookmark.objects.filter(user=request.user).values_list('question_id', flat=True))
    return render(request, 'search.html', {
        'questions': questions,
        'query': query,
        'user_bookmarks': user_bookmarks,
    })


@login_required
def toggle_bookmark(request, question_id):
    question = get_object_or_404(Question, id=question_id)
    bookmark, created = Bookmark.objects.get_or_create(user=request.user, question=question)
    if not created:
        bookmark.delete()
        status = 'removed'
    else:
        status = 'added'
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({'status': status})
    return redirect(request.META.get('HTTP_REFERER', 'all_questions'))


@login_required
def bookmarks(request):
    user_bookmarks = Bookmark.objects.filter(user=request.user).select_related('question')
    bookmark_ids = set(b.question_id for b in user_bookmarks)
    questions = [b.question for b in user_bookmarks]
    return render(request, 'bookmarks.html', {
        'questions': questions,
        'user_bookmarks': bookmark_ids,
    })


@login_required
def start_test(request):
    total_available = Question.objects.count()
    if request.method == 'POST':
        num_questions = int(request.POST.get('num_questions', 10))
        num_questions = min(num_questions, total_available)
        if num_questions < 1:
            num_questions = 1
        questions = list(Question.objects.all())
        random.shuffle(questions)
        selected = questions[:num_questions]
        session = TestSession.objects.create(
            user=request.user,
            total_questions=num_questions
        )
        session._selected_questions = [q.id for q in selected]
        request.session[f'test_{session.id}'] = {
            'question_ids': [q.id for q in selected],
            'current': 0,
            'answers': {},
            'time_limit': num_questions * 60,
        }
        return redirect('take_test', session_id=session.id)
    return render(request, 'start_test.html', {'total_available': total_available})


@login_required
def take_test(request, session_id):
    session = get_object_or_404(TestSession, id=session_id, user=request.user)
    if session.completed:
        return redirect('test_result', session_id=session.id)
    test_data = request.session.get(f'test_{session.id}')
    if not test_data:
        return redirect('start_test')
    question_ids = test_data['question_ids']
    questions = Question.objects.filter(id__in=question_ids)
    q_map = {q.id: q for q in questions}
    ordered_questions = [q_map[qid] for qid in question_ids if qid in q_map]
    return render(request, 'take_test.html', {
        'session': session,
        'questions': ordered_questions,
        'answers': test_data.get('answers', {}),
        'time_limit': test_data.get('time_limit', 600),
        'question_ids_json': json.dumps(question_ids),
    })


@login_required
def submit_test(request, session_id):
    session = get_object_or_404(TestSession, id=session_id, user=request.user)
    if session.completed:
        return redirect('test_result', session_id=session.id)
    test_data = request.session.get(f'test_{session.id}')
    if not test_data:
        return redirect('start_test')
    if request.method == 'POST':
        correct = 0
        wrong = 0
        time_spent = int(request.POST.get('time_spent', 0))
        question_ids = test_data['question_ids']
        questions = Question.objects.filter(id__in=question_ids)
        q_map = {q.id: q for q in questions}
        for qid in question_ids:
            answer = request.POST.get(f'answer_{qid}', '')
            q = q_map.get(qid)
            if q and answer:
                is_correct = answer.upper() == q.correct_answer
                if is_correct:
                    correct += 1
                else:
                    wrong += 1
                TestAnswer.objects.create(
                    session=session,
                    question=q,
                    selected_answer=answer.upper(),
                    is_correct=is_correct
                )
            elif q:
                wrong += 1
                TestAnswer.objects.create(
                    session=session,
                    question=q,
                    selected_answer='',
                    is_correct=False
                )
        session.correct_answers = correct
        session.wrong_answers = wrong
        session.time_spent = time_spent
        session.completed = True
        session.save()
        del request.session[f'test_{session.id}']
        request.session.modified = True
        return redirect('test_result', session_id=session.id)
    return redirect('take_test', session_id=session.id)


@login_required
def test_result(request, session_id):
    session = get_object_or_404(TestSession, id=session_id, user=request.user)
    answers = TestAnswer.objects.filter(session=session).select_related('question')
    return render(request, 'test_result.html', {
        'session': session,
        'answers': answers,
    })


@login_required
def statistics(request):
    sessions = TestSession.objects.filter(user=request.user, completed=True)
    total_tests = sessions.count()
    avg_score = 0
    best_score = 0
    total_questions_answered = 0
    total_correct = 0
    if sessions.exists():
        scores = [s.score_percent for s in sessions]
        avg_score = round(sum(scores) / len(scores))
        best_score = max(scores)
        total_questions_answered = sum(s.total_questions for s in sessions)
        total_correct = sum(s.correct_answers for s in sessions)
    recent_sessions = sessions[:10]
    return render(request, 'statistics.html', {
        'total_tests': total_tests,
        'avg_score': avg_score,
        'best_score': best_score,
        'total_questions_answered': total_questions_answered,
        'total_correct': total_correct,
        'recent_sessions': recent_sessions,
    })


@login_required
def profile(request):
    error = None
    success = None
    if request.method == 'POST':
        new_username = request.POST.get('new_username', '').strip()
        new_password = request.POST.get('new_password', '').strip()
        changed = False
        if new_username and new_username != request.user.username:
            if User.objects.filter(username=new_username).exclude(id=request.user.id).exists():
                error = "Bu login allaqachon mavjud!"
            else:
                request.user.username = new_username
                changed = True
        if new_password and not error:
            request.user.set_password(new_password)
            changed = True
        if changed and not error:
            request.user.save()
            login(request, request.user)
            success = "Ma'lumotlar muvaffaqiyatli yangilandi!"
    return render(request, 'profile.html', {'success': success, 'error': error})


@login_required
@user_passes_test(is_admin)
def admin_dashboard(request):
    total_questions = Question.objects.count()
    total_users = User.objects.filter(is_staff=False).count()
    total_tests = TestSession.objects.filter(completed=True).count()
    recent_tests = TestSession.objects.filter(completed=True).select_related('user')[:5]
    return render(request, 'admin/dashboard.html', {
        'total_questions': total_questions,
        'total_users': total_users,
        'total_tests': total_tests,
        'recent_tests': recent_tests,
    })


@login_required
@user_passes_test(is_admin)
def admin_questions(request):
    questions = Question.objects.all()
    return render(request, 'admin/questions.html', {'questions': questions})


def _parse_variants(post_data):
    letters = 'ABCDEFGHIJ'
    variants = []
    for letter in letters:
        val = post_data.get(f'variant_{letter.lower()}', '').strip()
        if val:
            variants.append({'letter': letter, 'text': val})
    return variants


@login_required
@user_passes_test(is_admin)
def admin_add_question(request):
    if request.method == 'POST':
        last = Question.objects.order_by('-number').first()
        next_num = (last.number + 1) if last else 1
        variants = _parse_variants(request.POST)
        q = Question(
            number=next_num,
            text=request.POST.get('text', ''),
            correct_answer=request.POST.get('correct_answer', 'A'),
        )
        q.variants = variants
        if 'image' in request.FILES:
            q.image = request.FILES['image']
        q.save()
        return redirect('admin_questions')
    return render(request, 'admin/add_question.html')


@login_required
@user_passes_test(is_admin)
def admin_edit_question(request, question_id):
    question = get_object_or_404(Question, id=question_id)
    if request.method == 'POST':
        question.text = request.POST.get('text', question.text)
        variants = _parse_variants(request.POST)
        question.variants = variants
        question.correct_answer = request.POST.get('correct_answer', question.correct_answer)
        if 'image' in request.FILES:
            question.image = request.FILES['image']
        if request.POST.get('remove_image') == 'on':
            question.image = None
        question.save()
        return redirect('admin_questions')
    return render(request, 'admin/edit_question.html', {'question': question})


@login_required
@user_passes_test(is_admin)
def admin_delete_question(request, question_id):
    question = get_object_or_404(Question, id=question_id)
    if request.method == 'POST':
        question.delete()
    return redirect('admin_questions')


@login_required
@user_passes_test(is_admin)
def admin_users(request):
    users = User.objects.filter(is_staff=False)
    return render(request, 'admin/users.html', {'users': users})


@login_required
@user_passes_test(is_admin)
def admin_add_user(request):
    error = None
    if request.method == 'POST':
        username = request.POST.get('username', '')
        password = request.POST.get('password', '')
        if User.objects.filter(username=username).exists():
            error = "Bu login allaqachon mavjud!"
        else:
            User.objects.create_user(username=username, password=password)
            return redirect('admin_users')
    return render(request, 'admin/add_user.html', {'error': error})


@login_required
@user_passes_test(is_admin)
def admin_edit_user(request, user_id):
    user = get_object_or_404(User, id=user_id, is_staff=False)
    error = None
    success = None
    if request.method == 'POST':
        new_username = request.POST.get('username', '')
        new_password = request.POST.get('password', '')
        if new_username != user.username and User.objects.filter(username=new_username).exists():
            error = "Bu login allaqachon mavjud!"
        else:
            user.username = new_username
            if new_password:
                user.set_password(new_password)
            user.save()
            success = "Foydalanuvchi muvaffaqiyatli yangilandi!"
    return render(request, 'admin/edit_user.html', {'edit_user': user, 'error': error, 'success': success})


@login_required
@user_passes_test(is_admin)
def admin_delete_user(request, user_id):
    user = get_object_or_404(User, id=user_id, is_staff=False)
    if request.method == 'POST':
        user.delete()
    return redirect('admin_users')


@login_required
@user_passes_test(is_admin)
def admin_statistics(request):
    users = User.objects.filter(is_staff=False)
    user_stats = []
    for u in users:
        sessions = TestSession.objects.filter(user=u, completed=True)
        total = sessions.count()
        avg = 0
        if sessions.exists():
            scores = [s.score_percent for s in sessions]
            avg = round(sum(scores) / len(scores))
        user_stats.append({
            'user': u,
            'total_tests': total,
            'avg_score': avg,
        })
    return render(request, 'admin/statistics.html', {'user_stats': user_stats})
