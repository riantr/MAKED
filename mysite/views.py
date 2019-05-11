from django.shorcuts import render, get_object_or_404
from .models import SiteSettingArticle
import markdown

def detail(request, article_id):
    article = get_object_or_404(SiteSettingArticle, pk=article_id)
    article.article_content = markdown.markdown(article.article_content.replace("\r\n"," \n"),
                        extensions=['markdown.extensions.extra',
                                    'markdown.extensions.codehilite',
                                    'markdown.extensions.toc',],safe_mode=True,enable_attributes=False)
    context = {
        'article': article,
    }
    return render(requet, 'mysite/detail.html',context)

def page_not_found(request):
    return render(request, 'mysite/404.html')
