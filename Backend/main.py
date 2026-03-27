from __future__ import annotations

import io
import logging
import os
import uuid
from time import perf_counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv
from PIL import Image, ImageOps

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("compress_api")

OUTPUT_DIR = Path(__file__).parent / "outputs"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
DEFAULT_MAX_SIDE = int(os.getenv("MAX_SIDE", "1600"))

app = FastAPI()

cors_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
if cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

SUPPORTED_FORMATS = {
    "jpeg": "JPEG",
    "jpg": "JPEG",
    "png": "PNG",
    "webp": "WEBP",
    "avif": "AVIF",
}


def clamp_quality(value: int) -> int:
    return max(1, min(100, value))


def png_compress_level_from_quality(quality: int) -> int:
    q = clamp_quality(quality)
    level = round((100 - q) * 9 / 100)
    return max(0, min(9, level))


def normalize_format(requested: Optional[str], detected: Optional[str]) -> str:
    if requested:
        key = requested.strip().lower()
    elif detected:
        key = detected.strip().lower()
    else:
        key = "jpeg"

    if key == "jpg":
        key = "jpeg"

    if key not in SUPPORTED_FORMATS:
        return "jpeg"
    return key


def ensure_format_supported(pil_format: str) -> None:
    available_formats = set(Image.registered_extensions().values())
    if pil_format not in available_formats:
        raise HTTPException(
            status_code=400,
            detail=f"Format {pil_format} is not supported by your Pillow build.",
        )


def _mime_for_format(fmt: str) -> str:
    if fmt == "jpeg":
        return "image/jpeg"
    if fmt == "png":
        return "image/png"
    if fmt == "webp":
        return "image/webp"
    if fmt == "avif":
        return "image/avif"
    return "application/octet-stream"


def _store_output(
    output_bytes: bytes,
    output_key: str,
    content_type: str,
    request: Request,
) -> str:
    output_path = OUTPUT_DIR / output_key
    output_path.write_bytes(output_bytes)
    return f"{str(request.base_url).rstrip('/')}/files/{output_key}"


def _compress_bytes(
    raw: bytes,
    original_name: str,
    quality: int,
    maxWidth: int | None,
    maxHeight: int | None,
    format: str | None,
    request: Request,
) -> dict:
    try:
        source = Image.open(io.BytesIO(raw))
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid image.") from exc

    source = ImageOps.exif_transpose(source)
    detected = source.format.lower() if source.format else None
    output_key = normalize_format(format, detected)
    pil_format = SUPPORTED_FORMATS[output_key]
    ensure_format_supported(pil_format)

    if maxWidth or maxHeight:
        target = (
            maxWidth if maxWidth and maxWidth > 0 else source.width,
            maxHeight if maxHeight and maxHeight > 0 else source.height,
        )
        source.thumbnail(target, Image.LANCZOS)
    elif DEFAULT_MAX_SIDE > 0:
        source.thumbnail((DEFAULT_MAX_SIDE, DEFAULT_MAX_SIDE), Image.LANCZOS)

    if pil_format == "JPEG" and source.mode not in ("RGB", "L"):
        source = source.convert("RGB")

    save_args = {}
    if pil_format == "JPEG":
        save_args["quality"] = clamp_quality(quality)
        save_args["optimize"] = True
    elif pil_format == "PNG":
        save_args["compress_level"] = png_compress_level_from_quality(quality)
        save_args["optimize"] = True
    elif pil_format == "WEBP":
        save_args["quality"] = clamp_quality(quality)
        save_args["method"] = 6
    elif pil_format == "AVIF":
        save_args["quality"] = clamp_quality(quality)

    output_buffer = io.BytesIO()
    source.save(output_buffer, format=pil_format, **save_args)
    output_bytes = output_buffer.getvalue()

    file_id = uuid.uuid4().hex
    extension = "jpg" if output_key == "jpeg" else output_key
    filename = f"{file_id}.{extension}"
    content_type = _mime_for_format(output_key)
    download_url = _store_output(output_bytes, filename, content_type, request)

    return {
        "id": file_id,
        "downloadUrl": download_url,
        "originalName": original_name,
        "originalSize": len(raw),
        "compressedSize": len(output_bytes),
        "format": output_key,
    }


@app.get("/api/health")
def health() -> dict:
    logger.info("Health check")
    return {"ok": True, "timestamp": datetime.now(timezone.utc).isoformat()}


@app.get("/")
def root() -> dict:
    logger.info("Root request")
    return {
        "message": "Compress Photo API is running.",
        "health": "/api/health",
        "compress": "/api/compress",
        "docs": "/docs",
    }


@app.post("/api/compress")
async def compress(
    request: Request,
    image: UploadFile = File(...),
    quality: int = Form(80),
    maxWidth: Optional[int] = Form(None),
    maxHeight: Optional[int] = Form(None),
    format: Optional[str] = Form(None),
) -> JSONResponse:
    start_time = perf_counter()
    if not image.filename:
        logger.warning("Upload missing filename")
        raise HTTPException(status_code=400, detail="Missing image filename.")

    raw = await image.read()
    if not raw:
        logger.warning("Empty upload for %s", image.filename)
        raise HTTPException(status_code=400, detail="Empty upload.")

    client = request.client.host if request.client else "unknown"
    logger.info(
        "Compress request from %s | name=%s | size=%s bytes",
        client,
        image.filename,
        len(raw),
    )
    try:
        result = _compress_bytes(
            raw=raw,
            original_name=image.filename,
            quality=quality,
            maxWidth=maxWidth,
            maxHeight=maxHeight,
            format=format,
            request=request,
        )
    except HTTPException:
        logger.warning("Invalid image upload for %s", image.filename)
        raise

    logger.info(
        "Compressed %s | output=%s bytes | url=%s",
        image.filename,
        result["compressedSize"],
        result["downloadUrl"],
    )
    logger.info("Compression time: %.2fs", perf_counter() - start_time)

    return JSONResponse(result)


app.mount("/files", StaticFiles(directory=OUTPUT_DIR), name="files")
