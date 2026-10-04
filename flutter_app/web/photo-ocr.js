/* Photos are decoded and recognized locally. Only language models are fetched. */
(function (scope) {
  'use strict';
  const languages = Object.freeze({
    de: 'deu', en: 'eng', fr: 'fra', es: 'spa', it: 'ita', pt: 'por',
    ja: 'jpn', ko: 'kor', 'zh-tw': 'chi_tra', zh: 'chi_sim', id: 'ind', th: 'tha',
  });
  let libraryPromise;
  let workerPromise;
  let workerLanguage;
  let reportProgress = () => {};
  let busy = false;

  function loadLibrary() {
    if (scope.Tesseract) return Promise.resolve(scope.Tesseract);
    if (!libraryPromise) {
      libraryPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = new URL('ocr/tesseract.min.js', document.baseURI).href;
        script.onload = () => scope.Tesseract ? resolve(scope.Tesseract) : reject(new Error('OCR_ENGINE_UNAVAILABLE'));
        script.onerror = () => { script.remove(); reject(new Error('OCR_ENGINE_UNAVAILABLE')); };
        document.head.appendChild(script);
      }).catch(error => { libraryPromise = undefined; throw error; });
    }
    return libraryPromise;
  }

  async function releaseWorker() {
    const previous = workerPromise;
    workerPromise = undefined;
    workerLanguage = undefined;
    if (previous) {
      try { await (await previous).terminate(); } catch (_) { /* Initialisation failed. */ }
    }
  }

  async function getWorker(language, isLive) {
    const tesseract = await loadLibrary();
    if (!isLive()) throw new Error('OCR_TIMEOUT');
    if (workerPromise && workerLanguage !== language) await releaseWorker();
    if (!isLive()) throw new Error('OCR_TIMEOUT');
    if (!workerPromise) {
      workerLanguage = language;
      const creation = tesseract.createWorker(language, 1, {
        workerPath: new URL('ocr/worker.min.js', document.baseURI).href,
        corePath: new URL('ocr/core/', document.baseURI).href,
        langPath: 'https://tessdata.projectnaptha.com/4.0.0_fast',
        // Same-origin worker runs without a remote script or photo upload.
        workerBlobURL: false,
        logger: message => {
          if (message.status === 'recognizing text') {
            reportProgress(`Kartentext wird gelesen … ${Math.round((message.progress || 0) * 100)} %`);
          } else if (message.status === 'loading language traineddata') {
            reportProgress(`Sprachdaten werden geladen … ${Math.round((message.progress || 0) * 100)} %`);
          } else reportProgress('Fotoerkennung wird vorbereitet …');
        },
      });
      workerPromise = creation;
      // If an abandoned initialization resolves after a timeout, release it.
      creation.then(worker => {
        if (workerPromise !== creation) return worker.terminate();
      }, () => {});
    }
    return workerPromise;
  }

  async function decode(bytes) {
    const blob = new Blob([bytes]);
    try {
      if (typeof createImageBitmap === 'function') return await createImageBitmap(blob);
      const url = URL.createObjectURL(blob);
      try {
        const image = new Image();
        image.src = url;
        await image.decode();
        return image;
      } finally { URL.revokeObjectURL(url); }
    } catch (_) { throw new Error('OCR_INVALID_IMAGE'); }
  }

  function prepare(image) {
    if (!image.width || !image.height) throw new Error('OCR_INVALID_IMAGE');
    const canvas = document.createElement('canvas');
    const scale = Math.min(1800 / image.width, 2800 / image.height);
    canvas.width = Math.max(1, Math.round(image.width * scale));
    canvas.height = Math.max(1, Math.round(image.height * scale));
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) throw new Error('OCR_INVALID_IMAGE');
    context.fillStyle = '#fff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.filter = 'grayscale(1) contrast(1.2)';
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  async function recognize(bytes, language, progress) {
    if (busy) throw new Error('OCR_BUSY');
    if (!(bytes instanceof Uint8Array) || !bytes.byteLength) throw new Error('OCR_INVALID_IMAGE');
    busy = true;
    let live = true;
    reportProgress = message => { if (live && typeof progress === 'function') progress(message); };
    let timer;
    let decoded;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('OCR_TIMEOUT')), 90000);
    });
    try {
      return await Promise.race([timeout, (async () => {
        reportProgress('Foto wird vorbereitet …');
        decoded = await decode(bytes);
        if (!live) {
          if (typeof decoded.close === 'function') decoded.close();
          throw new Error('OCR_TIMEOUT');
        }
        const canvas = prepare(decoded);
        const model = languages[language] || languages[language.split('-')[0]] || 'eng';
        const worker = await getWorker(model, () => live);
        if (!live) throw new Error('OCR_TIMEOUT');
        await worker.setParameters({ tessedit_pageseg_mode: '6' });
        const header = await worker.recognize(canvas, { rectangle: {
          left: 0, top: 0, width: canvas.width, height: Math.floor(canvas.height * .22),
        }});
        if (!live) throw new Error('OCR_TIMEOUT');
        await worker.setParameters({ tessedit_pageseg_mode: '11' });
        // Full image works for photos with margins; a separate bottom crop
        // increases resolution for the tiny printed collector number.
        const full = await worker.recognize(canvas);
        if (!live) throw new Error('OCR_TIMEOUT');
        let text = (header.data.text || '') + '\n' + (full.data.text || '');
        if (!/\b[A-Z]{0,3}\d{1,3}\s*[/／]\s*(?:[A-Z]{0,3}\d{2,3}|[A-Z]{1,3}-P)\b/i.test(text)) {
          const bottom = await worker.recognize(canvas, { rectangle: {
            left: 0, top: Math.floor(canvas.height * .72),
            width: canvas.width, height: Math.ceil(canvas.height * .28),
          }});
          text += '\n' + (bottom.data.text || '');
          if (!/\d{1,3}\s*\/\s*\d{2,3}/.test(text)) {
            await worker.setParameters({ tessedit_pageseg_mode: '7', tessedit_char_whitelist: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/' });
            const number = await worker.recognize(canvas, { rectangle: {
              left: 0, top: Math.floor(canvas.height * .94),
              width: Math.floor(canvas.width * .65), height: Math.ceil(canvas.height * .06),
            }});
            text += '\n' + (number.data.text || '');
            await worker.setParameters({ tessedit_char_whitelist: '' });
          }
        }
        return text;
      })()]);
    } catch (error) {
      // Clear broken worker state so the next photo can retry successfully.
      if (error.message !== 'OCR_INVALID_IMAGE') {
        const previous = workerPromise;
        workerPromise = undefined;
        workerLanguage = undefined;
        if (previous) previous.then(worker => worker.terminate(), () => {});
      }
      throw error;
    } finally {
      live = false;
      clearTimeout(timer);
      reportProgress = () => {};
      if (decoded && typeof decoded.close === 'function') decoded.close();
      busy = false;
    }
  }

  scope.pokeLensRecognizePhoto = recognize;
  function descriptor(image) {
    const canvas = document.createElement('canvas');
    canvas.width = 24;
    canvas.height = 34;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    const ratio = 24 / 34;
    let width = image.width;
    let height = image.height;
    if (width / height > ratio) width = height * ratio;
    else height = width / ratio;
    context.drawImage(image, (image.width - width) / 2, (image.height - height) / 2, width, height, 0, 0, 24, 34);
    return context.getImageData(0, 0, 24, 34).data;
  }

  scope.pokeLensRankCardImages = async function (bytes, urls) {
    const decoded = await decode(bytes);
    const photo = descriptor(decoded);
    if (typeof decoded.close === 'function') decoded.close();
    const scores = [];
    // Bound downloads, decoding and memory on phones and iPads.
    for (let offset = 0; offset < urls.length; offset += 6) {
      const group = urls.slice(offset, offset + 6);
      const results = await Promise.all(group.map(async (url, index) => {
        let score = Infinity;
        if (/^https:\/\/assets\.tcgdex\.net\//.test(url)) {
          const image = new Image();
          image.crossOrigin = 'anonymous';
          let timer;
          try {
            const loaded = new Promise((resolve, reject) => {
              image.onload = resolve;
              image.onerror = reject;
              timer = setTimeout(() => reject(new Error('image timeout')), 8000);
            });
            image.src = url.replace('/high.webp', '/low.webp');
            await loaded;
            const reference = descriptor(image);
            let distance = 0;
            for (let i = 0; i < photo.length; i += 4) {
              for (let channel = 0; channel < 3; channel++) distance += Math.abs(photo[i + channel] - reference[i + channel]);
            }
            score = distance / (photo.length * .75);
          } catch (_) { /* Keep unmatched images after successful comparisons. */ }
          finally { clearTimeout(timer); image.onload = image.onerror = null; }
        }
        return { index: offset + index, score };
      }));
      scores.push(...results);
    }
    scores.sort((a, b) => a.score - b.score || a.index - b.index);
    return scores.map(result => result.index);
  };
})(globalThis);
