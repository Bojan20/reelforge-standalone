/// <reference types="vite/client" />

// Worklet URL imports
declare module '*?worker&url' {
  const src: string;
  export default src;
}

// Audio file imports
declare module '*.mp3' {
  const src: string;
  export default src;
}

declare module '*.wav' {
  const src: string;
  export default src;
}
