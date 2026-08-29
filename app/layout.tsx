import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://nextmove-fouad.fouadmotaz25.chatgpt.site"),
  title: "NextMove | منصتك الرياضية",
  description: "احجز المنشآت الرياضية والتدريب والتغذية والتجهيزات من منصة عراقية واحدة.",
  icons: { icon: "/favicon.svg", apple: "/app-icon-180.png" },
  manifest: "/manifest.webmanifest",
  alternates: { canonical: "/" },
  openGraph: {
    title: "NextMove | حركتك القادمة تبدأ هنا",
    description: "رياضة وحجز وتدريب وتغذية في مكان واحد.",
    url: "/",
    siteName: "NextMove",
    images: ["/og.png"],
    locale: "ar_IQ",
    type: "website",
  },
  twitter: { card: "summary_large_image", title: "NextMove", description: "حركتك القادمة تبدأ هنا.", images: ["/og.png"] },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
