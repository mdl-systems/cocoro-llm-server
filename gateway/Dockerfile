FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn httpx
COPY anthropic_proxy.py .
CMD ["uvicorn", "anthropic_proxy:app", "--host", "0.0.0.0", "--port", "4001"]
