import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const h = await headers();
  const host = h.get("host") ?? "malabna.local";
  const protocol = host.includes("localhost") ? "http" : "https";
  const image = `${protocol}://${host}/og.png`;
  return {
    title: "ملعبنا | احجز ملعبك والعب",
    description: "احجز أفضل ملاعب كرة القدم بالقرب منك بسهولة وفي أقل من دقيقة.",
    icons: { icon: "/favicon.svg" },
    openGraph: { title: "ملعبنا | ملعبك جاهز", description: "اكتشف أفضل الملاعب واحجز موعدك في أقل من دقيقة.", images: [image], locale: "ar_IQ", type: "website" },
    twitter: { card: "summary_large_image", title: "ملعبنا | ملعبك جاهز", description: "والكرة بانتظارك.", images: [image] },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
