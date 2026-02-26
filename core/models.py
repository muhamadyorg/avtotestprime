import json
from django.db import models
from django.contrib.auth.models import User


LETTERS = 'ABCDEFGHIJ'


class Question(models.Model):
    number = models.PositiveIntegerField(unique=True)
    text = models.TextField()
    image = models.ImageField(upload_to='questions/', blank=True, null=True)
    variants_json = models.TextField(default='[]')
    correct_answer = models.CharField(max_length=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    variant_a = models.CharField(max_length=500, blank=True, default='')
    variant_b = models.CharField(max_length=500, blank=True, default='')
    variant_c = models.CharField(max_length=500, blank=True, default='')
    variant_d = models.CharField(max_length=500, blank=True, default='')

    class Meta:
        ordering = ['number']

    def __str__(self):
        return f"Savol #{self.number}"

    @property
    def variants(self):
        try:
            data = json.loads(self.variants_json)
            if data:
                return data
        except (json.JSONDecodeError, TypeError):
            pass
        result = []
        for field, letter in [('variant_a', 'A'), ('variant_b', 'B'), ('variant_c', 'C'), ('variant_d', 'D')]:
            val = getattr(self, field, '')
            if val:
                result.append({'letter': letter, 'text': val})
        return result

    @variants.setter
    def variants(self, value):
        self.variants_json = json.dumps(value, ensure_ascii=False)

    @property
    def variant_count(self):
        return len(self.variants)


class Bookmark(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='bookmarks')
    question = models.ForeignKey(Question, on_delete=models.CASCADE, related_name='bookmarks')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ['user', 'question']

    def __str__(self):
        return f"{self.user.username} - Savol #{self.question.number}"


class TestSession(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='test_sessions')
    total_questions = models.PositiveIntegerField()
    correct_answers = models.PositiveIntegerField(default=0)
    wrong_answers = models.PositiveIntegerField(default=0)
    time_spent = models.PositiveIntegerField(default=0)
    completed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.user.username} - {self.created_at.strftime('%Y-%m-%d %H:%M')}"

    @property
    def score_percent(self):
        if self.total_questions == 0:
            return 0
        return round((self.correct_answers / self.total_questions) * 100)


class TestAnswer(models.Model):
    session = models.ForeignKey(TestSession, on_delete=models.CASCADE, related_name='answers')
    question = models.ForeignKey(Question, on_delete=models.CASCADE)
    selected_answer = models.CharField(max_length=1)
    is_correct = models.BooleanField(default=False)

    def __str__(self):
        return f"Savol #{self.question.number} - {'correct' if self.is_correct else 'wrong'}"
