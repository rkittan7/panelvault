# The PDF and image work needs poppler, which is why this is its own process
# rather than something bolted onto the Node API (§3).
FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends poppler-utils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . /srv/scheme_extractor/
ENV PYTHONPATH=/srv SCHEME_CACHE_DIR=/var/cache/scheme_extractor
VOLUME ["/var/cache/scheme_extractor"]

EXPOSE 8100
CMD ["uvicorn", "scheme_extractor.api:app", "--host", "0.0.0.0", "--port", "8100"]
