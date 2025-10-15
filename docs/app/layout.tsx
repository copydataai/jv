import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "JV - Simple Java Build Tool for Students",
  description: "JV is a lightweight Java build tool designed for university assignments and simple projects. An alternative to Maven, Gradle, and Ant with zero configuration and fast setup.",
  keywords: ["java", "build tool", "maven alternative", "gradle alternative", "student projects", "java compiler", "cli tool"],
  authors: [{ name: "CopyData AI" }],
  creator: "CopyData AI",
  icons: {
    icon: "/jv.png",
    shortcut: "/jv.png",
    apple: "/jv.png",
  },
  openGraph: {
    title: "JV - Simple Java Build Tool for Students",
    description: "The simple Java build tool for students and early releases. Zero configuration, fast setup, student-friendly.",
    url: "https://jv.copydataai.com",
    siteName: "JV",
    type: "website",
    images: [
      {
        url: "/jv.png",
        width: 1200,
        height: 630,
        alt: "JV Logo",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "JV - Simple Java Build Tool for Students",
    description: "The simple Java build tool for students and early releases. Zero configuration, fast setup, student-friendly.",
    images: ["/jv.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
