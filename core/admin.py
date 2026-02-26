from django.contrib import admin
from .models import Question, Bookmark, TestSession, TestAnswer

admin.site.register(Question)
admin.site.register(Bookmark)
admin.site.register(TestSession)
admin.site.register(TestAnswer)
