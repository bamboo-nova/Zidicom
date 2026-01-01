import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface WasmExports {
  memory: WebAssembly.Memory;
  wasmAlloc: (size: number) => number;
  wasmFree: (ptr: number, size: number) => void;
  getLastError: () => number;
  getLastErrorLen: () => number;
  wasmGetMemoryStats: () => number;
  testAdd: (a: number, b: number) => number;
  getDicomDimensions: (
    dicomPtr: number,
    dicomLen: number,
    widthOut: number,
    heightOut: number
  ) => number;
  extractMetadataJson: (
    dicomPtr: number,
    dicomLen: number,
    jsonPtrOut: number
  ) => number;
  convertDicomToRGB: (
    dicomPtr: number,
    dicomLen: number,
    resultPtrOut: number
  ) => number;
}

interface DicomMetadata {
  patientName?: string;
  patientID?: string;
  studyDate?: string;
  modality?: string;
  rows?: number;
  columns?: number;
  [key: string]: any;
}

interface DicomDimensions {
  width: number;
  height: number;
}

interface RGBImageData {
  data: Uint8Array;
  width: number;
  height: number;
}

class DicomWasm {
  private instance: WebAssembly.Instance | null = null;
  private memory: WebAssembly.Memory | null = null;
  private exports: WasmExports | null = null;

  async init(wasmPath: string = '../zig-out/wasm/dicom_wasm.wasm'): Promise<void> {
    const wasmBuffer = fs.readFileSync(path.join(__dirname, wasmPath));
    const wasmModule = await WebAssembly.compile(wasmBuffer);

    const imports = {
      env: {
        // Environment functions that WASM might need
      }
    };

    this.instance = await WebAssembly.instantiate(wasmModule, imports);
    this.exports = this.instance.exports as unknown as WasmExports;
    this.memory = this.exports.memory;

    console.log('WASM module loaded successfully');
    console.log('Available exports:', Object.keys(this.exports));
  }

  private ensureInitialized(): void {
    if (!this.exports || !this.memory) {
      throw new Error('WASM module not initialized. Call init() first.');
    }
  }

  private allocateAndCopy(data: Uint8Array): { ptr: number; size: number } {
    this.ensureInitialized();
    const ptr = this.exports!.wasmAlloc(data.length);
    if (ptr === 0) {
      throw new Error('Failed to allocate memory');
    }
    const view = new Uint8Array(this.memory!.buffer, ptr, data.length);
    view.set(data);
    return { ptr, size: data.length };
  }

  private readString(ptr: number, len: number): string {
    this.ensureInitialized();
    const view = new Uint8Array(this.memory!.buffer, ptr, len);
    return new TextDecoder().decode(view);
  }

  private readU32(ptr: number): number {
    this.ensureInitialized();
    const view = new DataView(this.memory!.buffer, ptr, 4);
    return view.getUint32(0, true); // little-endian
  }

  getLastError(): string | null {
    this.ensureInitialized();
    const errPtr = this.exports!.getLastError();
    const errLen = this.exports!.getLastErrorLen();
    if (errLen === 0) {
      return null;
    }
    return this.readString(errPtr, errLen);
  }

  testAdd(a: number, b: number): number {
    this.ensureInitialized();
    return this.exports!.testAdd(a, b);
  }

  async getDimensions(dicomBuffer: Uint8Array): Promise<DicomDimensions> {
    this.ensureInitialized();
    const { ptr, size } = this.allocateAndCopy(dicomBuffer);

    try {
      // Allocate space for output
      const widthOutPtr = this.exports!.wasmAlloc(4);
      const heightOutPtr = this.exports!.wasmAlloc(4);

      const result = this.exports!.getDicomDimensions(ptr, size, widthOutPtr, heightOutPtr);

      if (result !== 0) {
        const error = this.getLastError();
        throw new Error(`Failed to get dimensions: ${error}`);
      }

      const width = this.readU32(widthOutPtr);
      const height = this.readU32(heightOutPtr);

      // Free allocated memory
      this.exports!.wasmFree(widthOutPtr, 4);
      this.exports!.wasmFree(heightOutPtr, 4);

      return { width, height };
    } finally {
      this.exports!.wasmFree(ptr, size);
    }
  }

  async extractMetadata(dicomBuffer: Uint8Array): Promise<DicomMetadata> {
    this.ensureInitialized();
    const { ptr, size } = this.allocateAndCopy(dicomBuffer);

    try {
      // Allocate space for output (ptr + len)
      const jsonOutPtr = this.exports!.wasmAlloc(8);

      const result = this.exports!.extractMetadataJson(ptr, size, jsonOutPtr);

      if (result !== 1) {
        const error = this.getLastError();
        throw new Error(`Failed to extract metadata: ${error}`);
      }

      // Read the JSON pointer and length
      const jsonPtr = this.readU32(jsonOutPtr);
      const jsonLen = this.readU32(jsonOutPtr + 4);

      // Read the JSON string
      const jsonStr = this.readString(jsonPtr, jsonLen);

      // Free allocated memory
      this.exports!.wasmFree(jsonPtr, jsonLen);
      this.exports!.wasmFree(jsonOutPtr, 8);

      return JSON.parse(jsonStr);
    } finally {
      this.exports!.wasmFree(ptr, size);
    }
  }

  getMemoryStats(): number {
    this.ensureInitialized();
    return this.exports!.wasmGetMemoryStats();
  }

  async convertToRGB(dicomBuffer: Uint8Array): Promise<RGBImageData> {
    this.ensureInitialized();
    const { ptr, size } = this.allocateAndCopy(dicomBuffer);

    try {
      // Allocate space for output (ptr, length, width, height)
      const resultOutPtr = this.exports!.wasmAlloc(16);

      const result = this.exports!.convertDicomToRGB(ptr, size, resultOutPtr);

      if (result !== 0) {
        const error = this.getLastError();
        throw new Error(`Failed to convert DICOM to RGB: ${error}`);
      }

      // Read the result
      const rgbPtr = this.readU32(resultOutPtr);
      const rgbLen = this.readU32(resultOutPtr + 4);
      const width = this.readU32(resultOutPtr + 8);
      const height = this.readU32(resultOutPtr + 12);

      // Read RGB data
      const rgbData = new Uint8Array(this.memory!.buffer, rgbPtr, rgbLen);
      const rgbCopy = new Uint8Array(rgbData); // Create a copy

      // Free allocated memory
      this.exports!.wasmFree(rgbPtr, rgbLen);
      this.exports!.wasmFree(resultOutPtr, 16);

      return {
        data: rgbCopy,
        width,
        height,
      };
    } finally {
      this.exports!.wasmFree(ptr, size);
    }
  }

  async convertToPNG(dicomBuffer: Uint8Array): Promise<string> {
    let rgbImage: RGBImageData;

    try {
      // Try WASM first (for uncompressed DICOM)
      rgbImage = await this.convertToRGB(dicomBuffer);
    } catch (error) {
      // If WASM fails (likely compressed DICOM), use native CLI tool
      const errorMessage = error instanceof Error ? error.message : '';
      if (errorMessage.includes('compressed') || errorMessage.includes('UnsupportedTransferSyntax')) {
        rgbImage = await this.convertToRGBNative(dicomBuffer);
      } else {
        throw error;
      }
    }

    // Use canvas to convert RGB data to PNG
    // For Node.js, we'll return a data URL that can be used in the browser
    const { createCanvas } = await import('canvas');
    const canvas = createCanvas(rgbImage.width, rgbImage.height);
    const ctx = canvas.getContext('2d');

    // Create ImageData from RGB data
    const imageData = ctx.createImageData(rgbImage.width, rgbImage.height);
    for (let i = 0; i < rgbImage.data.length / 3; i++) {
      imageData.data[i * 4] = rgbImage.data[i * 3];     // R
      imageData.data[i * 4 + 1] = rgbImage.data[i * 3 + 1]; // G
      imageData.data[i * 4 + 2] = rgbImage.data[i * 3 + 2]; // B
      imageData.data[i * 4 + 3] = 255; // A (fully opaque)
    }

    ctx.putImageData(imageData, 0, 0);

    // Convert to PNG data URL
    return canvas.toDataURL('image/png');
  }

  private async convertToRGBNative(dicomBuffer: Uint8Array): Promise<RGBImageData> {
    const { spawn } = await import('child_process');
    const fs = await import('fs/promises');
    const path = await import('path');
    const os = await import('os');
    const { fileURLToPath } = await import('url');

    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);

    const cliPath = path.join(__dirname, '../zig-out/bin/dicom-to-rgb');

    // Write DICOM data to temporary file
    const tmpFile = path.join(os.tmpdir(), `dicom-${Date.now()}.dcm`);
    const tmpOut = path.join(os.tmpdir(), `dicom-${Date.now()}.rgb`);
    await fs.writeFile(tmpFile, dicomBuffer);

    try {
      return await new Promise((resolve, reject) => {
        const process = spawn(cliPath, [tmpFile, tmpOut]);

        process.stderr.on('data', (data) => {
          console.error('CLI error:', data.toString());
        });

        process.on('close', async (code) => {
          // Clean up input file
          try {
            await fs.unlink(tmpFile);
          } catch (e) {
            // Ignore cleanup errors
          }

          if (code !== 0) {
            reject(new Error(`CLI tool exited with code ${code}`));
            return;
          }

          try {
            // Read output file
            const buffer = await fs.readFile(tmpOut);

            // Clean up output file
            await fs.unlink(tmpOut);

            if (buffer.length < 8) {
              reject(new Error('Invalid output from CLI tool'));
              return;
            }

            // Read width and height
            const width = buffer.readUInt32LE(0);
            const height = buffer.readUInt32LE(4);
            const rgbData = new Uint8Array(buffer.buffer, buffer.byteOffset + 8, buffer.length - 8);

            resolve({
              data: rgbData,
              width,
              height,
            });
          } catch (error) {
            reject(error);
          }
        });
      });
    } catch (error) {
      // Ensure temp files are cleaned up even if promise rejects
      try {
        await fs.unlink(tmpFile);
      } catch (e) {
        // Ignore cleanup errors
      }
      try {
        await fs.unlink(tmpOut);
      } catch (e) {
        // Ignore cleanup errors
      }
      throw error;
    }
  }
}

export default DicomWasm;
