'use client';

import { useEffect, useRef } from 'react';

type CandlesProps = {
  symbol: string;
  height?: number;            // optional height from the page
  intervalMinutes?: number;   // reserved for future use (live intervals)
};

export default function Candles({ symbol, height = 320, intervalMinutes = 1 }: CandlesProps) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const draw = () => {
    const wrap = wrapRef.current;
    const canvas = canvasRef.current;
    if (!wrap || !canvas) return;

    const DPR = Math.max(1, Math.min(3, window.devicePixelRatio || 1));
    const Wcss = wrap.clientWidth || 600;
    const Hcss = height;

    // size canvas for crisp drawing
    canvas.style.width = `${Wcss}px`;
    canvas.style.height = `${Hcss}px`;
    canvas.width = Math.floor(Wcss * DPR);
    canvas.height = Math.floor(Hcss * DPR);

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Crisp drawing at device pixel ratio
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);

    // clear
    ctx.clearRect(0, 0, Wcss, Hcss);

    // axes
    ctx.strokeStyle = '#1f2937';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(40, 10);
    ctx.lineTo(40, Hcss - 20);
    ctx.lineTo(Wcss - 10, Hcss - 20);
    ctx.stroke();

    // title
    ctx.fillStyle = '#cbd5e1';
    ctx.font = '12px ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto';
    ctx.fillText(`${symbol} (${intervalMinutes}m)`, 50, 22);

    // dashed placeholder candles (until live candles land)
    const left = 48;
    const right = Wcss - 16;
    const width = right - left;
    const bars = Math.max(8, Math.floor(width / 20));
    const baseY = Hcss - 26;

    ctx.setLineDash([4, 4]);
    for (let i = 0; i < bars; i++) {
      const x = left + (i / bars) * width;
      const bodyH = 10 + ((i * 37) % 28);
      const high = baseY - bodyH - 6 - (i % 3 === 0 ? 8 : 0);
      const low = baseY + 3 - (i % 4 === 0 ? 3 : 0);

      ctx.strokeStyle = i % 2 ? '#16a34a' : '#ef4444';

      // wick
      ctx.beginPath();
      ctx.moveTo(x, high);
      ctx.lineTo(x, low);
      ctx.stroke();

      // body
      ctx.beginPath();
      ctx.moveTo(x - 4, baseY - bodyH);
      ctx.lineTo(x + 4, baseY - bodyH);
      ctx.lineTo(x + 4, baseY);
      ctx.lineTo(x - 4, baseY);
      ctx.closePath();
      ctx.stroke();
    }
    ctx.setLineDash([]);
  };

  useEffect(() => {
    draw();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [symbol, height, intervalMinutes]);

  useEffect(() => {
    const wrap = wrapRef.current;
    if (!wrap) return;
    const ro = new ResizeObserver(() => draw());
    ro.observe(wrap);
    return () => ro.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div ref={wrapRef} className="w-full">
      <canvas ref={canvasRef} className="block w-full h-auto rounded-md" />
    </div>
  );
}
