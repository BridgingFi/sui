import { useClipboard } from "@heroui/use-clipboard";
import { Button, ButtonProps, Tooltip, TooltipProps } from "@heroui/react";
import { Check, Copy } from "iconoir-react";

interface CopyButtonProps extends Omit<ButtonProps, "onPress" | "onCopy"> {
  /**
   * The value to copy to clipboard
   */
  value: string;
  /**
   * Custom icon to show when copied
   */
  checkIcon?: React.ReactElement;
  /**
   * Custom icon to show when not copied
   */
  copyIcon?: React.ReactElement;
  /**
   * The time in milliseconds to wait before resetting the clipboard state
   * @default 2000
   */
  timeout?: number;
  /**
   * Callback when the text is copied
   */
  onCopy?: (details: { copied: boolean }) => void;
  /**
   * Whether to hide the tooltip
   * @default false
   */
  disableTooltip?: boolean;
  /**
   * Tooltip props
   * @see [Tooltip](https://heroui.com/components/tooltip) for more details
   * @default {
   *   offset: 15,
   *   delay: 1000,
   *   content: "Copy to clipboard",
   * }
   */
  tooltipProps?: Partial<TooltipProps>;
}

/**
 * Copy button component using HeroUI's useClipboard hook
 * Based on HeroUI's use-snippet.ts implementation pattern
 * @see https://github.com/heroui-inc/heroui/blob/canary/packages/components/snippet/src/use-snippet.ts
 */
export function CopyButton({
  value,
  checkIcon = <Check className="w-4 h-4" />,
  copyIcon = <Copy className="w-4 h-4" />,
  timeout = 2000,
  onCopy: onCopyProp,
  disableTooltip = false,
  tooltipProps: userTooltipProps = {},
  ...buttonProps
}: CopyButtonProps) {
  const { copy, copied } = useClipboard({ timeout });

  // Default tooltip props similar to use-snippet.ts
  const tooltipProps: Partial<TooltipProps> = {
    offset: 15,
    delay: 1000,
    content: "Copy to clipboard",
    ...userTooltipProps,
  };

  // Default button props similar to use-snippet.ts
  const defaultButtonProps: Partial<ButtonProps> = {
    "aria-label":
      typeof tooltipProps.content === "string"
        ? tooltipProps.content
        : "Copy to clipboard",
    size: "sm",
    variant: "light",
    isIconOnly: true,
    onPress: () => {
      copy(value);
      if (onCopyProp) {
        onCopyProp({ copied: true });
      }
    },
    ...buttonProps,
  };

  const copyButton = (
    <Button {...defaultButtonProps}>{copied ? checkIcon : copyIcon}</Button>
  );

  if (disableTooltip) {
    return copyButton;
  }

  return <Tooltip {...tooltipProps}>{copyButton}</Tooltip>;
}
