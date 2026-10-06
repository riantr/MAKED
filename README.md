# MAKED

**M**odel · **A**ttack · **K**nowledge · **E**xperience · **D**ata

*The framework for automated AI testing.*

MAKED is a Django CMS site that organises an automated-AI-testing knowledge
base into five domains. The logo draws them as a closed ring around a centre:
each domain is a stage that consumes what the previous one produced.

| Letter | Domain        | Role in the original site   |
|--------|---------------|-----------------------------|
| **M**  | Model         | the model formulator        |
| **A**  | Attack        | the attack generator        |
| **K**  | Knowledge     | the knowledge distiller     |
| **E**  | Experience    | the experience absorber     |
| **D**  | Data          | the data turbine            |

The five names are not decoration. Each one is a Django application
(`Model/`, `Attack/`, `Knowledge/`, `Experience/`, `Data/`) **and** a top-level
CMS page, so the navigation of the site is the ontology of the project. `Data`
carries the real data model (`Dataset`, `Image`, `ImageInfo`); the other four
are placeholders for the work still to come.

---

## Running it

```bash
python -m virtualenv .venv                       # or: python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt

.\.venv\Scripts\python manage.py migrate
.\.venv\Scripts\python manage.py bootstrap_maked   # creates the 9 pages
.\.venv\Scripts\python manage.py createsuperuser

.\.venv\Scripts\python manage.py runserver 127.0.0.1:8000
```

Then open <http://127.0.0.1:8000/> and log in at `/admin/`.

This sequence was verified end to end from a fresh clone on Python 3.13.14:
`requirements.txt` resolved without conflict, `migrate` applied cleanly,
`bootstrap_maked` created all nine pages, `collectstatic` gathered 1067 files,
and every page, the admin (23 changelists) and the REST API returned 200.

> **The port and `MAKED_SITE_DOMAIN` are coupled.** django CMS matches the
> request `Host` header against the `Site` row's `domain`, and the bootstrap
> command writes `127.0.0.1:8000` into it. If you serve on a different port,
> set the domain to match or every page will redirect to the page-content
> admin instead of rendering:
>
> ```bash
> MAKED_SITE_DOMAIN=127.0.0.1:8765 python manage.py bootstrap_maked --delete
> MAKED_SITE_DOMAIN=127.0.0.1:8765 python manage.py runserver 127.0.0.1:8765
> ```
>
> (Port 8000 is already taken on some machines, so this comes up often.)

`bootstrap_maked` is idempotent. Pass `--delete` to rebuild the page tree from
scratch.

### Background tasks

```bash
celery -A mysite worker --loglevel=info
celery -A mysite beat   --loglevel=info
celery -A mysite flower --address=127.0.0.1 --port=5555
```

Celery needs a Redis broker. Without one, the site still serves pages; only the
scheduled tasks are unavailable. `Knowledge.tasks.fetch_article` is inert
unless `MAKED_KNOWLEDGE_SOURCE_URL` points at a feed.

### Configuration

Everything is read from the environment; no secret is stored in the repository.

| Variable | Default | Purpose |
|---|---|---|
| `MAKED_SECRET_KEY` | insecure dev fallback | **Set this in production.** |
| `MAKED_DEBUG` | `true` | Set `false` to enable the production security settings. |
| `MAKED_ALLOWED_HOSTS` | `localhost,127.0.0.1,[::1]` | Comma-separated. |
| `MAKED_SITE_DOMAIN` | `127.0.0.1:8000` | The `Site` row's domain; must match the URL you browse to. |
| `MAKED_CSRF_TRUSTED_ORIGINS` | empty | Comma-separated origins. |
| `MAKED_CELERY_BROKER` | `redis://127.0.0.1:6379/0` | Broker URL. |
| `MAKED_KNOWLEDGE_SOURCE_URL` | empty | Feed for `fetch_article`; unset means the task does nothing. |
| `MAKED_HSTS_SECONDS` | `0` | Opt in only after TLS is confirmed working. |
| `MAKED_SSL_REDIRECT` | `false` | Opt in only if Django terminates TLS itself. |

### Verifying a deployment

```bash
.\.venv\Scripts\python manage.py check
.\.venv\Scripts\python manage.py test Knowledge
.\.venv\Scripts\python tools\verify_site.py http://127.0.0.1:8000
.\.venv\Scripts\python tools\verify_admin.py http://127.0.0.1:8000
```

- `verify_site.py` — every page renders its content (not just HTTP 200), the
  navigation exposes all five domains, and an authenticated admin can reach the
  django CMS page editor.
- `verify_admin.py` — logs in and loads every changelist in the admin registry.
  Both read the URL list from the live registry rather than hard-coding it: the
  `Data` app's label is capitalised, so its changelist is at
  `/admin/Data/dataset/`, and celery-beat's `PeriodicTask` has no underscore.
  Three models (`cms.Page`, `cms.Placeholder`, `djangocms_link.Link`) are
  registered but hidden from the admin nav by design, because django CMS edits
  them inside the page editor; the test records and skips them rather than
  asserting a status code that is an implementation detail.
- `scan_history.py` — reads every blob in the git object database looking for
  key material and hard-coded secrets.

---

## What the modernisation changed

The original project was written in 2019 against Django 2.1.8 and django CMS
3.6. Neither can be installed on a supported Python, so the stack moved to
**Django 5.2 LTS + django CMS 5.1**. Django 4.2 was rejected as the target: its
LTS window closed in April 2026, and django CMS 5.1 requires `Django>=5.2`
anyway.

### The database could not be migrated

`legacy_MAKED_cms36.db` is the original SQLite file, preserved unmodified. It
uses the django CMS 3.6 *publisher* schema, which stored a separate draft and
published row for every page. django CMS 4.0 deleted the publisher entirely,
so that schema cannot be migrated forward.

The page tree was therefore recreated on the current schema by
`manage.py bootstrap_maked`, which encodes the structure the original database
described: 9 pages (Index, the five domains, Tutorial, About, celery task
monitor), the domain logos, and the site's one-line descriptions. The images
themselves are the originals, copied out of the old filer tree by
`tools/copy_logos.py`.

### Bugs fixed

These were real defects in the original, not just API drift.

- `mysite/views.py` — `detail()` raised `NameError` on every call: it imported
  `django.shorcuts` (typo) and passed `requet` to `render()`. It also called
  `markdown.markdown(..., safe_mode=True)`, an argument removed in Markdown 3.0.
- `mysite/views.py` — the view rendered `mysite/detail.html`, but the template
  is `detail.html`. The view was also never routed: every `path()` call in the
  original `urlpatterns` list was commented out, so `detail()` was unreachable.
  The route is now registered at `/articles/<id>/`.
- `Data/models.py` — `ImageInfo.color_space` declared `max_length=10` while its
  choices contained `"ColorMatchRGB"` (13 characters). Django 2.1 did not check
  this; Django 5 does. Widened to 16 (`Data/migrations/0011_*.py`).
- `mysite/settings.py` — `PASSWORD_HASHERS` was never set. With no Argon2 or
  bcrypt installed, Django falls back to *unsalted* PBKDF2-SHA1, and
  `createsuperuser` stores a password that `authenticate()` then cannot read
  back — the hasher cannot even be identified from the stored value. The
  hashers are now declared explicitly and `argon2-cffi` is a hard requirement.
- `mysite/celery.py` — set `app.now = timezone.now`, which is not a Celery
  attribute; the line was dead code. Priority queues were configured twice (once
  on `app.conf`, once on a module-level name that was never read), so only one
  of the two schemes was ever live.
- `mysite/urls.py` — the original shadowed `FlatPageAdmin` with a class of the
  same name, and registered admin models at import time around
  `admin.autodiscover()`.

### Security

- `SECRET_KEY` was hard-coded in `settings.py` and also reused as
  `HASHID_FIELD_SALT`. Both now come from the environment.
- `DEBUG = True` and `ALLOWED_HOSTS = ['*']` were hard-coded. Both are
  environment-driven, and the production block (HSTS, secure cookies,
  `X-Frame-Options`, `nosniff`, referrer policy) is now real.
- The repository tracked a **TLS private key** (`server.key`), its certificate,
  a **90 MB Redis dump** (`dump.rdb`), `celerybeat.pid`, 117 `.pyc` files, an
  unrelated `libcloud/KEYS` file, and a stale `Data.bak/` copy of the Data app.
  All were removed from **every commit** with `git filter-repo`, and are covered
  by `.gitignore` going forward.

  The certificate was a self-signed local debugging pair that never served any
  real traffic, so no key rotation was required. The `SECRET_KEY` that was hard
  coded in `settings.py` across seven historical commits was replaced in those
  commits too, not just in the working tree.

  Because the history was rewritten, **all commit SHAs changed** — pushing
  requires `--force-with-lease`:

  ```bash
  git push --force-with-lease origin master
  ```

### What is still publicly reachable on GitHub

The rewrite is complete on Gitee. On GitHub it is complete on the branches but
**not everywhere**, and this is a property of the platform rather than of the
rewrite:

| Ref | State |
|---|---|
| `refs/heads/master` | clean — the private key is not in its tree |
| `refs/heads/dependabot/pip/django-2.2.24` | deleted |
| `refs/pull/1..6/head` | **still expose the old history** |

GitHub refuses to delete pull-request refs outright:

```
DELETE /repos/riantr/MAKED/git/refs/pull/6/head
422 Unprocessable Entity
{"message": "refs/pull/* is read-only."}
```

That is a platform-level restriction, not a permissions problem: the request
was made with a `repo`-scoped token by an account with admin rights on the
repository. So this is still fetchable by anyone:

```bash
git fetch https://github.com/riantr/MAKED.git refs/pull/6/head
git show FETCH_HEAD:server.key      # the private key
git show FETCH_HEAD:dump.rdb        # 90 MB
```

The six pull requests were all Dependabot bumps of Django 2.1.8 to 2.2.x and
are obsolete — the project now runs Django 5.2. Removing the exposure
completely therefore means deleting the repository and re-creating it under the
same name, which discards those pull request records along with the objects.
That trade has not been made.

**None of the exposed material is an active credential.** The certificate was a
local self-signed debugging pair. The `SECRET_KEY` is no longer used by the
running site (it comes from the environment now, and falls back to an
explicitly-labelled development key). The Redis dump held only Celery's
pidbox, worker event stream and queue bindings, with zero `celery-task-meta`
entries — no task payloads. `tools/inspect_dump_rdb.py` will print that summary
for any dump you want to check.

  Verify a rewrite with:

  ```bash
  python tools/scan_history.py
  ```

  It reads every blob in the object database, not just reachable files, and
  reports private-key blocks, cloud credentials and hard-coded secrets with
  the path each came from.

### Dependencies dropped

| Removed | Why |
|---|---|
| `django-mdeditor`, `django-markdown-deux` | Unmaintained; no Django 4+ release. The article body is a plain `TextField` and Markdown is rendered in the view. |
| `djangocms-snippet` | Version 5.x hard-depends on `djangocms-versioning`, which must be a separately installed app with its own settings. The original site stored **zero** snippets. |
| `djangocms-googlemap`, `djangocms-column`, `djangocms-video` | No release compatible with django CMS 5. The original database holds zero rows for all three. |
| `django-parler`, `django-mptt` | Transitive dependencies of the old plugin set. |

Kept and pinned: `Django`, `django-cms`, `djangocms-text-ckeditor`,
`djangocms-link`, `djangocms-picture`, `djangocms-file`, `djangocms-style`,
`django-filer`, `easy-thumbnails`, `celery`, `django-celery-beat`,
`django-celery-results`, `djangorestframework`, `Markdown`, `argon2-cffi`.

### The Knowledge task

`Knowledge.tasks.fetch_article` was a bare `print`, scheduled every five
minutes — the old database records 131,739 runs of it. It is implemented for
real now: it fetches a configured feed, de-duplicates by title, and returns a
summary dict. It never raises, so a scheduled failure cannot spam the result
table. Twelve tests cover the parsers, the no-source case, the de-duplication,
and the network-failure paths.

---

## Layout

```
mysite/          project config, settings, urls, celery app, templates
Model/           M — the model formulator        (placeholder)
Attack/          A — the attack generator        (placeholder)
Knowledge/       K — the knowledge distiller     (has the fetch task)
Experience/      E — the experience absorber     (placeholder)
Data/            D — the data turbine            (Dataset, Image, ImageInfo)
tools/           copy_logos.py, trace_urls.py, verify_site.py,
                 verify_admin.py, verify_markdown_view.py,
                 scan_history.py, inspect_dump_rdb.py
legacy_MAKED_cms36.db   the original django CMS 3.6 database, untouched
```

## Licence

MIT — see `LICENSE`.
