FROM python:3.13-slim
COPY --from=ghcr.io/astral-sh/uv:0.12.17 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
COPY src ./src
RUN uv sync --frozen --no-dev
ENV PATH="/app/.venv/bin:$PATH" \
    BIND_HOST=0.0.0.0 \
    PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "-m", "mini_dfs"]
