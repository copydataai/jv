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
  authors: [{ name: "Jose Sanchez" }],
  creator: "Jose Sanchez",
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
