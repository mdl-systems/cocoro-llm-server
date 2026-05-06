import type { Metadata } from "next";
import { Inter, Roboto_Mono } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });
const robotoMono = Roboto_Mono({ subsets: ["latin"], variable: "--font-roboto-mono" });

export const metadata: Metadata = {
  title: "NEXUS-X | Ultimate Gaming PC",
  description: "Experience the future of gaming with the most powerful PC ever built",
  keywords: ["gaming PC", " premium PC", "high performance", "gaming computer", "NEXUS-X"],
  authors: [{ name: "NEXUS-X Team" }],
  openGraph: {
    title: "NEXUS-X | Ultimate Gaming PC",
    description: "Experience the future of gaming",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${inter.variable} ${robotoMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
