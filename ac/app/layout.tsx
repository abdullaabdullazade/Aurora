export const metadata = {
  title: 'Aurora Resolver Registry',
  description: 'Points the Aurora app to the current backend URL',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body style={{ margin: 0 }}>{children}</body>
    </html>
  );
}
