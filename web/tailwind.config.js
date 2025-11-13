import { heroui } from "@heroui/react";

/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{ts,tsx}",
    "./node_modules/@heroui/theme/dist/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: "class",
  plugins: [
    heroui({
      themes: {
        dark: {
          fontFamily: {
            sans: ["Inter", "ui-sans-serif", "system-ui", "sans-serif"],
          },
          colors: {
            primary: {
              50: "#f3f0ff",
              100: "#e9e5ff",
              200: "#d6ceff",
              300: "#b8a6ff",
              400: "#9575ff",
              500: "#6c5ecf",
              600: "#5a4bb8",
              700: "#4c3d9a",
              800: "#3f347c",
              900: "#352e65",
              950: "#1f1a3a",
              DEFAULT: "#6c5ecf",
              foreground: "#ffffff",
            },
            secondary: {
              50: "#11254b",
              100: "#1a3b77",
              200: "#2451a3",
              300: "#2d66cf",
              400: "#377cfb",
              500: "#5a93fc",
              600: "#7daafc",
              700: "#a0c1fd",
              800: "#c3d8fe",
              900: "#e6efff",
              foreground: "#000",
              DEFAULT: "#377cfb",
            },
          },
        },
      },
    }),
  ],
};
