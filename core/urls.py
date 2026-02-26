from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('login/', views.login_view, name='login'),
    path('logout/', views.logout_view, name='logout'),

    path('dashboard/', views.dashboard, name='dashboard'),
    path('questions/', views.all_questions, name='all_questions'),
    path('questions/<int:question_id>/', views.question_detail, name='question_detail'),
    path('search/', views.search_questions, name='search_questions'),
    path('bookmark/toggle/<int:question_id>/', views.toggle_bookmark, name='toggle_bookmark'),
    path('bookmarks/', views.bookmarks, name='bookmarks'),
    path('test/start/', views.start_test, name='start_test'),
    path('test/<int:session_id>/', views.take_test, name='take_test'),
    path('test/<int:session_id>/submit/', views.submit_test, name='submit_test'),
    path('test/<int:session_id>/result/', views.test_result, name='test_result'),
    path('statistics/', views.statistics, name='statistics'),
    path('profile/', views.profile, name='profile'),

    path('panel/', views.admin_dashboard, name='admin_dashboard'),
    path('panel/questions/', views.admin_questions, name='admin_questions'),
    path('panel/questions/add/', views.admin_add_question, name='admin_add_question'),
    path('panel/questions/<int:question_id>/edit/', views.admin_edit_question, name='admin_edit_question'),
    path('panel/questions/<int:question_id>/delete/', views.admin_delete_question, name='admin_delete_question'),
    path('panel/users/', views.admin_users, name='admin_users'),
    path('panel/users/add/', views.admin_add_user, name='admin_add_user'),
    path('panel/users/<int:user_id>/edit/', views.admin_edit_user, name='admin_edit_user'),
    path('panel/users/<int:user_id>/delete/', views.admin_delete_user, name='admin_delete_user'),
    path('panel/statistics/', views.admin_statistics, name='admin_statistics'),
]
