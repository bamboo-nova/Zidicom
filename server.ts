import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import DicomWasm from './dicom-wasm.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = 3000;

// Initialize WASM module
const dicomWasm = new DicomWasm();
await dicomWasm.init();

// Middleware
app.use(express.json());
app.use(express.raw({ type: 'application/octet-stream', limit: '50mb' }));

// Serve static files
app.use(express.static(path.join(__dirname, '../public')));
app.use('/wasm', express.static(path.join(__dirname, '../zig-out/wasm')));

// API: Test endpoint
app.get('/api/test', (req, res) => {
  const result = dicomWasm.testAdd(5, 10);
  res.json({ result, message: 'WASM test successful' });
});

// API: Get DICOM metadata
app.post('/api/dicom/metadata', async (req, res) => {
  try {
    const dicomBuffer = new Uint8Array(req.body);
    const metadata = await dicomWasm.extractMetadata(dicomBuffer);
    res.json({ success: true, metadata });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(400).json({ success: false, error: errorMessage });
  }
});

// API: Get DICOM dimensions
app.post('/api/dicom/dimensions', async (req, res) => {
  try {
    const dicomBuffer = new Uint8Array(req.body);
    const dimensions = await dicomWasm.getDimensions(dicomBuffer);
    res.json({ success: true, dimensions });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(400).json({ success: false, error: errorMessage });
  }
});

// API: Get DICOM info (metadata + dimensions)
app.post('/api/dicom/info', async (req, res) => {
  try {
    const dicomBuffer = new Uint8Array(req.body);
    const metadata = await dicomWasm.extractMetadata(dicomBuffer);
    const dimensions = await dicomWasm.getDimensions(dicomBuffer);
    res.json({
      success: true,
      metadata,
      dimensions,
      memoryUsed: dicomWasm.getMemoryStats()
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(400).json({ success: false, error: errorMessage });
  }
});

// API: Convert DICOM to PNG image
app.post('/api/dicom/image', async (req, res) => {
  try {
    const dicomBuffer = new Uint8Array(req.body);
    const pngDataUrl = await dicomWasm.convertToPNG(dicomBuffer);
    res.json({ success: true, image: pngDataUrl });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(400).json({ success: false, error: errorMessage });
  }
});

// API: List sample DICOM files
app.get('/api/samples', (req, res) => {
  const samples = fs.readdirSync(__dirname + '/..')
    .filter(file => file.endsWith('.dcm'))
    .map(file => ({
      name: file,
      size: fs.statSync(path.join(__dirname, '..', file)).size
    }));
  res.json({ success: true, samples });
});

// API: Load sample DICOM file
app.get('/api/sample/:filename', (req, res) => {
  try {
    const filename = req.params.filename;
    if (!filename.endsWith('.dcm')) {
      res.status(400).json({ success: false, error: 'Invalid file type' });
      return;
    }
    const filePath = path.join(__dirname, '..', filename);
    if (!fs.existsSync(filePath)) {
      res.status(404).json({ success: false, error: 'File not found' });
      return;
    }
    const buffer = fs.readFileSync(filePath);
    res.set('Content-Type', 'application/dicom');
    res.send(buffer);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ success: false, error: errorMessage });
  }
});

app.listen(PORT, () => {
  console.log(`DICOM Viewer server running at http://localhost:${PORT}`);
  console.log(`WASM module initialized with memory: ${dicomWasm.getMemoryStats()} bytes`);
});
