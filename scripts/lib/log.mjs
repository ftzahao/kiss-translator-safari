const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code) => (s) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : String(s));

export const bold = c("1");
export const dim = c("2");
export const green = c("32");
export const yellow = c("33");
export const red = c("31");
export const cyan = c("36");

export const step = (msg) => console.log(`\n${cyan("==>")} ${bold(msg)}`);
export const info = (msg) => console.log(`    ${msg}`);
export const ok = (msg) => {
  console.log(`    ${green("✓")} ${msg}`);
  return msg;
};
export const warn = (msg) => console.warn(`    ${yellow("!")} ${msg}`);
export const fail = (msg) => console.error(`    ${red("✗")} ${msg}`);
