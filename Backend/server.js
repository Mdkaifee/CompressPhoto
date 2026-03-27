const express = require('express');
const cors = require('cors');
const multer = require('multer');
const sharp = require('sharp');
const path = require('path');
const fs = require('fs');
const fsp = require('fs/promises');
const { randomUUID } = require('crypto');

const PORT = process.env.PORT || 5000;
const OUTPUT_DIR = path.join(__dirname, 'outputs');

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

const app = express();
app.use(cors());
app.use(express.json({ limit: '1mb' }));

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 25 * 1024 * 1024
  }
});

function parsePositiveInt(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.floor(n);
}

function normalizeFormat(format, metadataFormat) {
  const raw = (format || metadataFormat || 'jpeg').toLowerCase();
  if (raw === 'jpg') return 'jpeg';
  if (raw === 'jpeg' || raw === 'png' || raw === 'webp' || raw === 'avif') {
    return raw;
  }
  return 'jpeg';
}

function extensionForFormat(format) {
  if (format === 'jpeg') return 'jpg';
  return format;
}

function pngCompressionLevelFromQuality(quality) {
  // Quality 1-100 mapped to compressionLevel 9-0 (higher quality -> lower compression)
  const q = Math.max(1, Math.min(100, quality));
  const level = Math.round((100 - q) * 9 / 100);
  return Math.max(0, Math.min(9, level));
}

app.get('/api/health', (req, res) => {
  res.json({ ok: true, timestamp: new Date().toISOString() });
});

app.post('/api/compress', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded. Use field name "image".' });
    }

    const quality = parsePositiveInt(req.body.quality, 80);
    const maxWidth = parsePositiveInt(req.body.maxWidth, null);
    const maxHeight = parsePositiveInt(req.body.maxHeight, null);
    const format = req.body.format;

    const inputBuffer = req.file.buffer;
    const base = sharp(inputBuffer, { failOn: 'none' });
    const metadata = await base.metadata();

    const outputFormat = normalizeFormat(format, metadata.format);
    let pipeline = sharp(inputBuffer, { failOn: 'none' });

    if (maxWidth || maxHeight) {
      pipeline = pipeline.resize({
        width: maxWidth || null,
        height: maxHeight || null,
        fit: 'inside',
        withoutEnlargement: true
      });
    }

    if (outputFormat === 'jpeg') {
      pipeline = pipeline.jpeg({ quality });
    } else if (outputFormat === 'png') {
      pipeline = pipeline.png({ compressionLevel: pngCompressionLevelFromQuality(quality) });
    } else if (outputFormat === 'webp') {
      pipeline = pipeline.webp({ quality });
    } else if (outputFormat === 'avif') {
      pipeline = pipeline.avif({ quality });
    }

    const outputBuffer = await pipeline.toBuffer();
    const id = randomUUID();
    const ext = extensionForFormat(outputFormat);
    const outputName = `${id}.${ext}`;
    const outputPath = path.join(OUTPUT_DIR, outputName);

    await fsp.writeFile(outputPath, outputBuffer);

    const downloadUrl = `${req.protocol}://${req.get('host')}/files/${outputName}`;

    return res.json({
      id,
      downloadUrl,
      originalName: req.file.originalname,
      originalSize: req.file.size,
      compressedSize: outputBuffer.length,
      format: outputFormat
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: 'Compression failed.' });
  }
});

app.use('/files', express.static(OUTPUT_DIR, {
  fallthrough: false,
  maxAge: '1h'
}));

app.use((err, req, res, next) => {
  if (err && err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'File too large. Max 25MB.' });
  }
  return next(err);
});

app.listen(PORT, () => {
  console.log(`Backend running on http://localhost:${PORT}`);
});
