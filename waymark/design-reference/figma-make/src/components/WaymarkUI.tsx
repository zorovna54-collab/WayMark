import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  SelectHTMLAttributes,
  HTMLAttributes,
  Ref,
} from "react"

export function Button({
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button className={`wm-button ${className}`} {...props} />
}
export function TextField(
  props: InputHTMLAttributes<HTMLInputElement> & {
    ref?: Ref<HTMLInputElement>
  },
) {
  return <input {...props} className={`wm-field ${props.className || ""}`} />
}
export function SelectField(props: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select {...props} className={`wm-field ${props.className || ""}`} />
}
export function Title(props: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 {...props} />
}
export default Button
