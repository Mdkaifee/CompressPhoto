# Compress Photo Backend (FastAPI)

This backend accepts an image upload, compresses it, and returns a download URL.

## Features
- Upload + compress in one request
- No database required
- Download the compressed file via a static URL

## Requirements
- Python 3.10+

## Setup (macOS/Linux)
```bash
cd Backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

## Setup (Windows)
> If you're on macOS/Linux, don't use the commands in this section. They will fail in `zsh` (because Windows uses `Scripts\\activate`, macOS/Linux uses `bin/activate`).

```bat
cd Backend
py -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

## API Endpoints
- `GET /` -> basic info
- `GET /api/health` -> health check
- `POST /api/compress` -> upload + compress
- `GET /files/{filename}` -> download compressed file

## POST /api/compress
**Form-data fields**
- `image` (file) **required**
- `quality` (int, 1-100) default `80`
- `maxWidth` (int, optional)
- `maxHeight` (int, optional)
- `format` (string: `jpeg`, `png`, `webp`, `avif`)

**Example (curl)**
```bash
curl -F "image=@/path/to/photo.jpg" \
  -F "quality=75" \
  -F "maxWidth=1200" \
  -F "format=jpeg" \
  http://127.0.0.1:8000/api/compress
```

## Storage
Compressed files are saved locally in `Backend/outputs`.

**Response**
```json
{
  "id": "<uuid>",
  "downloadUrl": "http://127.0.0.1:8000/files/<uuid>.jpg",
  "originalName": "photo.jpg",
  "originalSize": 345678,
  "compressedSize": 123456,
  "format": "jpeg"
}
```

## Notes
- Compressed files are stored in `Backend/outputs`.
- For Android emulator (FastAPI on your host), use `http://10.0.2.2:8000` in the Flutter app.
- For a real phone, use your computer's LAN IP (example: `http://192.168.1.10:8000`).
- `AVIF` support depends on your Pillow build.

## Optional: expose with ngrok
If you want to call your local backend from a real device without being on the same LAN, you can use ngrok:
```bash
ngrok http 8000
```
Then put the `https://<your-subdomain>.ngrok-free.dev` URL into the Flutter app's **Backend URL** field.
